const std = @import("std");

const MAX_KEY_LEN = 512;
const MAX_VALUE_LEN = std.fs.max_path_bytes - MAX_KEY_LEN;

pub const env_parser = @This();

pub fn parseFilePath(allocator: std.mem.Allocator, out_map: std.StringHashMap([]const u8), absolute_path: []const u8) !void {
    const file = try std.fs.openFileAbsolute(absolute_path, .{ .mode = .read_only });
    defer file.close();
    parseFile(allocator, out_map, &file);
}

pub fn parseFile(allocator: std.mem.Allocator, out_map: *std.StringHashMap([]const u8), file: *const std.fs.File) !void {
    const reader = file.*.reader();

    var buf: [4096:0]u8 = undefined;
    const end: usize = try reader.read(&buf);
    var start: usize = 0;
    while (true) {
        if (buf[start] == 0 or start >= end) break;
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
            start += line_end + pos;
            try out_map.put(try allocator.dupe(u8, key[0..pos]), try allocator.dupe(u8, value[0 .. line_end - 1]));
        }
    }
}
