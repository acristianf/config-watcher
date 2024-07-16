const std = @import("std");
const env_parser = @import("env-parser.zig");
const Allocator = std.mem.Allocator;
const FBA = std.heap.FixedBufferAllocator;

const MAX_LINE_SIZE = 256 + std.fs.max_path_bytes;

pub fn main() !void {
    const HOME_DIR = std.posix.getenv("HOME") orelse return error.HomeEnvNotSet;

    var args = std.process.args();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--set-folder")) {
            const path = args.next() orelse {
                std.log.err("[ERROR] Expected path after '--set-folder'\n", .{});
                return;
            };
            var realpathbuf = [_]u8{'A'} ** std.fs.max_path_bytes;
            const realpath = std.fs.realpath(path, &realpathbuf) catch |err| {
                std.log.err("[ERROR] Couldn't read path '{s}'. Error: {!} \n", .{ path, err });
                return;
            };
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            var fba = FBA.init(&buf);
            const fbaallocator = fba.allocator();
            const watcher = concat(fbaallocator, HOME_DIR, "/.watcher") catch |err| {
                std.log.err("[ERROR] {!} \n", .{err});
                return;
            };
            std.fs.makeDirAbsolute(watcher) catch |err| {
                switch (err) {
                    error.PathAlreadyExists => {},
                    else => {
                        std.log.err("[ERROR] Unexpected error creating '.watcher' folder on home. Error: {!} \n", .{err});
                        return;
                    },
                }
            };
            var watcher_dir = std.fs.openDirAbsolute(watcher, .{}) catch |err| {
                switch (err) {
                    error.AccessDenied => {
                        std.log.err("[ERROR] Access Denied trying to open folder '{s}' \n", .{watcher});
                    },
                    else => {
                        std.log.err("[ERROR] Unexpected error. Error: {!} \n", .{err});
                    },
                }
                return;
            };
            defer watcher_dir.close();
            var watcher_file = watcher_dir.createFile("watcher.env", .{ .truncate = false }) catch |err| {
                switch (err) {
                    error.AccessDenied => {
                        std.log.err("[ERROR] Access Denied trying to create/open 'watcher.env' \n", .{});
                    },
                    else => {
                        std.log.err("[ERROR] Unexpected error trying to create/open 'watcher.env'. Error: {!} \n", .{err});
                    },
                }
                return;
            };
            defer watcher_file.close();
            try watcher_file.seekFromEnd(0);
            fba.reset();
            const folderconfig = try concat(fbaallocator, "folder=", realpath);
            _ = try watcher_file.write(folderconfig);
            _ = try watcher_file.write("\n");
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaa);
    const aa = arena.allocator();
    defer arena.deinit();

    const config_file_path = try concat(aa, HOME_DIR, "/.watcher/watcher.env");

    var config_map = std.StringHashMap([]const u8).init(aa);
    defer config_map.deinit();

    const file = try std.fs.openFileAbsolute(config_file_path, .{});
    try env_parser.parseFile(aa, &config_map, &file);
    std.debug.print("{?s}\n", .{config_map.get("folder")});
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
