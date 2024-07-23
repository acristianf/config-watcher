const std = @import("std");
const utils = @import("utils.zig").utils;
const PathStructureError = @import("r_errors.zig").PathStructureError;
const WatcherConfErrors = @import("r_errors.zig").WatcherConfErrors;
const WatcherConfig = @import("s_config.zig").WatcherConfig;

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
