const std = @import("std");
const pow = @import("std").math.pow;
const Allocator = @import("std").mem.Allocator;
const utils = @import("utils.zig").utils;
const WatcherConfErrors = @import("r_errors.zig").r_errors.WatcherConfErrors;
const defines = @import("defines.zig").defines;

pub const s_config = @This();

const MAX_KEY_LEN = 512;
const MAX_VALUE_LEN = std.fs.max_path_bytes - MAX_KEY_LEN;

pub fn parseConfig(aa: Allocator) !WatcherConfig {
    return try WatcherConfig.init(aa);
}

const ConfigData = struct {
    start_pos: defines.max_config_file_size,
    value: []const u8,
};

pub const WatcherConfig = struct {
    allocator: Allocator,
    home_dir: []const u8,

    // Configuration specific
    folder: ?ConfigData,
    repo: ?ConfigData,

    const config_path_leaf = "/.watcher/watcher.env";
    const Self = @This();

    pub fn init(allocator: Allocator) !WatcherConfig {
        const home_dir = std.posix.getenv("HOME") orelse return WatcherConfErrors.HomeEnvNotSet;

        // Load config file
        const config_file_path = try utils.concat(allocator, home_dir, Self.config_path_leaf);

        var config_map = std.StringHashMap(ConfigData).init(allocator);
        defer config_map.deinit();

        const file = try std.fs.openFileAbsolute(config_file_path, .{});
        defer file.close();
        try parseConfigFile(allocator, &config_map, &file);

        var f = config_map.get("folder") orelse null;

        if (f) |setted_folder| {
            if (setted_folder.value[setted_folder.value.len - 1] != '/') {
                f.?.value = try utils.concat(allocator, setted_folder.value, "/");
            }
        }

        return .{ .folder = f, .repo = config_map.get("repo") orelse null, .home_dir = home_dir, .allocator = allocator };
    }
};

fn read(out: []u8, reader: anytype) !defines.max_config_file_size {
    const r = try reader.read(out);
    const truncated: defines.max_config_file_size = @truncate(r);
    if (truncated != r) {
        std.log.err("File size read={d}GB, File size max={d}GB\n", .{
            utils.bytesToGB(r),
            utils.bytesToGB(pow(usize, 2, @sizeOf(defines.max_config_file_size))),
        });
        return WatcherConfErrors.ConfigFileSizeTooLong;
    }
    return truncated;
}

fn parseConfigFile(
    allocator: std.mem.Allocator,
    out_map: *std.StringHashMap(ConfigData),
    file: *const std.fs.File,
) !void {
    const reader = file.*.reader();

    var buf: [4096:0]u8 = undefined;

    var end: defines.max_config_file_size = try read(&buf, reader);
    var start: defines.max_config_file_size = 0;
    var f_offset: defines.max_config_file_size = 0;
    while (true) {
        if (buf[start] == 0 or start >= end) {
            // Try reading more
            end = try read(&buf, reader);
            if (end == 0) break;
            // Accum offset
            f_offset += start;
            start = 0;
            continue;
        }
        if (std.ascii.isWhitespace(buf[start])) {
            start += 1;
            continue;
        }
        // Found first '='
        if (std.mem.indexOfScalar(u8, buf[start..end], '=')) |pos| {
            // Find '\n'
            const line_end = std.mem.indexOfScalar(u8, buf[start + pos .. end], '\n') orelse break; // Hit EOF?
            var key: [MAX_KEY_LEN:0]u8 = undefined;
            var value: [MAX_VALUE_LEN:0]u8 = undefined;
            if (pos > MAX_KEY_LEN) return error.ConfigKeyTooLong;
            if (line_end - 1 > MAX_VALUE_LEN) return error.ConfigValueTooLong;
            @memcpy(key[0..pos], buf[start .. start + pos]);
            @memcpy(value[0 .. line_end - 1], buf[start + pos + 1 .. start + pos + line_end]);
            const off: u32 = @truncate(line_end + pos);
            start += off;
            try out_map.put(
                try allocator.dupe(u8, key[0..pos]),
                .{
                    .start_pos = start + f_offset,
                    .value = try allocator.dupe(u8, value[0 .. line_end - 1]),
                },
            );
        }
    }
}

test "Detect Leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    defer _ = gpa.detectLeaks();

    var arena = std.heap.ArenaAllocator.init(gpaa);
    defer arena.deinit();

    const aa = arena.allocator();
    _ = try WatcherConfig.init(aa);
}
