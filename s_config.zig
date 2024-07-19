const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const utils = @import("utils.zig").utils;
const env_parser = @import("env-parser.zig").env_parser;
const WatcherConfErrors = @import("r_errors.zig").r_errors.WatcherConfErrors;

const s_config = @This();

pub fn parseConfig(aa: Allocator) !WatcherConfig {
    return try WatcherConfig.init(aa);
}

pub const WatcherConfig = struct {
    allocator: Allocator,
    home_dir: []const u8,

    // Configuration specific
    folder: ?[]const u8,
    repo: ?[]const u8,

    const config_path_leaf = "/.watcher/watcher.env";
    const Self = @This();

    pub fn init(allocator: Allocator) !WatcherConfig {
        const home_dir = std.posix.getenv("HOME") orelse return WatcherConfErrors.HomeEnvNotSet;

        // Load config file
        const config_file_path = try utils.concat(allocator, home_dir, Self.config_path_leaf);

        var config_map = std.StringHashMap([]const u8).init(allocator);
        defer config_map.deinit();

        const file = try std.fs.openFileAbsolute(config_file_path, .{});
        try env_parser.parseFile(allocator, &config_map, &file);

        return .{ .folder = config_map.get("folder") orelse null, .repo = config_map.get("repo") orelse null, .home_dir = home_dir, .allocator = allocator };
    }
};

test "Detect Leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    defer _ = gpa.detectLeaks();

    var arena = std.heap.ArenaAllocator.init(gpaa);
    defer arena.deinit();

    const aa = arena.allocator();
    _ = try WatcherConfig.init(aa);
}
