const std = @import("std");
const utils = @import("utils.zig").utils;
const PathStructureError = @import("r_errors.zig").PathStructureError;
const WatcherConfErrors = @import("r_errors.zig").WatcherConfErrors;
const WatcherConfig = @import("s_config.zig").WatcherConfig;
const defines = @import("defines.zig");
const MyersDiff = @import("lib/diff.zig").MyersDiff;

pub const fsmanip = @This();

fn validateStructure(structure: []const u8) PathStructureError!void {
    if (structure.len == 1 and structure[0] == '.') return PathStructureError.RelativePathsNotSupported;
    if (structure.len > 1 and structure[0] == '.' and structure[1] == '/') return PathStructureError.RelativePathsNotSupported;
    if (structure.len == 2 and structure[0] == '.' and structure[1] == '.') return PathStructureError.RelativePathsNotSupported;
    if (structure.len >= 2 and structure[0] == '.' and structure[1] == '.' and structure[2] == '/') return PathStructureError.RelativePathsNotSupported;
}

fn cleanSlashes(out_buffer: []u8, structure: []const u8) []u8 {
    var i: usize = 0;
    var written: usize = 0;
    while (i < structure.len) : (i += 1) {
        if (structure[i] == '/') {
            out_buffer[written] = '/';
            written += 1;
            // Discard repeating slashes
            for (i..structure.len) |end| {
                if (structure[end] != '/') break;
                i = end;
            }
        } else {
            out_buffer[written] = structure[i];
            written += 1;
        }
    }
    out_buffer[written] = 0;
    return out_buffer[0..written];
}

pub fn createStructurePath(allocator: std.mem.Allocator, container_folder: []const u8, structure: []const u8) ![]u8 {
    try validateStructure(structure);
    const c = try utils.concat(allocator, container_folder, structure);
    defer allocator.free(c);
    const out = try allocator.alloc(u8, c.len);
    return cleanSlashes(out, c);
}

/// Creates a directory structure inside the designated
/// config container folder
pub fn mkStructure(container_folder: []const u8, structure_path_absolute: []const u8) !std.fs.Dir {
    // Alloc 40kb of stack memory
    var buf: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    var path_names_iterator = std.mem.splitScalar(u8, structure_path_absolute, '/');
    var leaf = container_folder;
    while (path_names_iterator.next()) |path| {
        if (path.len == 0) continue;
        if (leaf[leaf.len - 1] != '/') {
            leaf = try utils.concat(fba.allocator(), leaf, "/");
        }

        leaf = try utils.concat(fba.allocator(), leaf, path);

        std.fs.makeDirAbsolute(leaf) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };
    }

    return try std.fs.openDirAbsolute(leaf, .{});
}

pub fn copyDirectory(dir: std.fs.Dir, container_folder: []const u8, relative_structure: []u8) !void {
    var tmp_buf: [std.fs.max_path_bytes - 1:0]u8 = undefined;
    const structure = try fsmanip.mkStructure(container_folder, relative_structure);
    var dir_iterator = dir.iterate();
    while (try dir_iterator.next()) |item| {
        switch (item.kind) {
            std.fs.File.Kind.directory => {
                if (utils.sIncludes([]const u8, &defines.EXCLUDE_DIRS, item.name)) continue;
                var inner = try dir.openDir(item.name, .{ .iterate = true });
                defer inner.close();
                const new_structure = try std.fmt.bufPrintZ(&tmp_buf, "{s}/{s}", .{ relative_structure, item.name });
                try copyDirectory(inner, container_folder, new_structure);
            },
            std.fs.File.Kind.file => {
                try dir.copyFile(item.name, structure, item.name, .{});
            },
            else => {
                std.log.warn("ignore unknown file kind", .{});
            },
        }
    }
}

pub fn updateFiles(allocator: std.mem.Allocator, dir: std.fs.Dir, real_path: []const u8) !void {
    std.log.info("analyzing '{s}'", .{real_path});
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const f = try dir.openFile(entry.name, .{});
                var buf: [std.fs.max_path_bytes - 1:0]u8 = undefined;
                const real_file_path = try std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ real_path, entry.name });
                const real_f = std.fs.openFileAbsolute(real_file_path, .{}) catch |err| {
                    switch (err) {
                        error.FileNotFound => {
                            std.log.info("{s} not found. Skipping..", .{real_file_path});
                            continue;
                        },
                        else => return err,
                    }
                };
                defer real_f.close();
                const c = try allocator.alloc(u8, (try f.stat()).size);
                defer allocator.free(c);
                const real_c = try allocator.alloc(u8, (try real_f.stat()).size);
                defer allocator.free(real_c);
                var differ = try MyersDiff(u8).init(allocator, c, real_c);
                f.close();
                if (try differ.distance() != 0) {
                    try dir.copyFile(real_file_path, dir, entry.name, .{});
                    std.log.info("\tupdating {s}...", .{entry.name});
                }
            },
            .directory => {
                if (utils.sIncludes([]const u8, &defines.EXCLUDE_DIRS, entry.name)) continue;
                var inner = try dir.openDir(entry.name, .{ .iterate = true });
                defer inner.close();
                var buf: [std.fs.max_path_bytes - 1:0]u8 = undefined;
                const p = try std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ real_path, entry.name });
                try updateFiles(allocator, inner, p);
            },
            else => std.log.warn("unknown file type {any}", .{entry.kind}),
        }
    }
}
