const std = @import("std");
const Allocator = std.mem.Allocator;
const FBA = std.heap.FixedBufferAllocator;

const MAX_LINE_SIZE = 256 + std.fs.max_path_bytes;

const FixedBuffer = struct {};

const WatcherConfig = struct {
    folder: []const u8 = undefined,

    fn init(f: std.fs.File) !WatcherConfig {
        var config = WatcherConfig{};
        const reader = f.reader();
        var buf: [MAX_LINE_SIZE]u8 = undefined;
        var i: u32 = 0;
        while (true) {
            const byte = reader.readByte() catch |err| {
                switch (err) {
                    error.EndOfStream => {
                        break;
                    },
                    else => {
                        return err;
                    },
                }
            };
            if (byte == '\n') {
                if (i > MAX_LINE_SIZE) return error.ConfigLineTooLong;
                var c: u32 = 0;
                while (buf[c] != '=' and c <= i) {
                    c += 1;
                }
                const key = buf[0..c];
                // Ignore '='
                const value = buf[c + 2 .. i + 1];
                if (std.mem.eql(u8, key, "FOLDER")) {
                    config.folder = value;
                }
                i = 0;
            }
            buf[i] = byte;
            i += 1;
        }
        return config;
    }
};

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
    const file = try std.fs.openFileAbsolute("/home/cristian/.watcher/watcher.env", .{});
    const config = try WatcherConfig.init(file);
    std.debug.print("{s}\n", .{config.folder});
}

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
