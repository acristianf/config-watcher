const std = @import("std");
const utils = @import("utils.zig").utils;
const PathStructureError = @import("r_errors.zig").PathStructureError;
const WatcherConfErrors = @import("r_errors.zig").WatcherConfErrors;
const WatcherConfig = @import("s_config.zig").WatcherConfig;

const fsmanip = @This();

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

/// Creates a directory structure inside the designated
/// config container folder
pub fn mkStructure(config: WatcherConfig, structure: []const u8) !std.fs.Dir {
    try validateStructure(structure);

    // Alloc 40kb of stack memory
    var buf: [4096 * 10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const container_folder = config.folder orelse return WatcherConfErrors.ContainerFolderNotSet;
    const final_cont_folder = if (container_folder[container_folder.len - 1] != '/') try utils.concat(fba.allocator(), container_folder, "/") else container_folder;

    var clean_buf: [std.fs.max_path_bytes - 1]u8 = undefined;
    const clean_structure = cleanSlashes(&clean_buf, structure);

    var path_names_iterator = std.mem.splitScalar(u8, clean_structure, '/');
    var leaf = final_cont_folder;
    while (path_names_iterator.next()) |path| {
        if (path.len == 0) continue;
        if (leaf[leaf.len - 1] != '/') {
            leaf = try utils.concat(fba.allocator(), leaf, "/");
        }

        leaf = try utils.concat(fba.allocator(), leaf, path);

        try std.fs.makeDirAbsolute(leaf);
    }

    return try std.fs.openDirAbsolute(leaf, .{});
}

test "mkStructure" {
    var buf: [1024 * 1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const fbaa = fba.allocator();
    const c = try WatcherConfig.init(fbaa);
    const dir = try mkStructure(c, "/.config/nvim");
    std.debug.print("{any}\n", .{dir});
}

// test "path making" {
//     var buf: [1024 * 1000]u8 = undefined;
//     var fba = std.heap.FixedBufferAllocator.init(&buf);
//     const fbaa = fba.allocator();
//     const c = try WatcherConfig.init(fbaa);
//     const container_folder = c.folder orelse return WatcherConfErrors.ContainerFolderNotSet;
//     const concatenated = try utils.concat(fba.allocator(), container_folder, "/.config/nvim");
//     std.debug.print("{c} {d}\n", .{ concatenated[0], concatenated.len });
// }
