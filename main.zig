const std = @import("std");
const Allocator = std.mem.Allocator;
const FBA = std.heap.FixedBufferAllocator;

pub fn main() !void {
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
            const homedir = std.posix.getenv("HOME") orelse {
                std.log.err("[ERROR] Couldn't read '$HOME' \n", .{});
                return;
            };
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            var fba = FBA.init(&buf);
            const fbaallocator = fba.allocator();
            const watcher = concat(fbaallocator, homedir, "/.watcher") catch |err| {
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
            const folderconfig = try concat(fbaallocator, "FOLDER=", realpath);
            _ = try watcher_file.write(folderconfig);
            _ = try watcher_file.write("\n");
        }
    }
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
