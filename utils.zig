const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const defines = @import("defines.zig").defines;

pub const utils = @This();

pub fn bytesToGB(bytes: usize) usize {
    return bytes / defines.BYTE_TO_GB_FACTOR;
}

/// Validating using POSIX Portable filename character set
/// [A-Za-Z0-9._-]
pub fn validLinuxPath(path: []const u8) bool {
    var last_char: u8 = '!';
    for (path) |char| {
        switch (char) {
            '/' => if (last_char == '/') return false,
            '.', '_', '-', 'A'...'Z', 'a'...'z', '0'...'9' => {},
            else => return false,
        }
        last_char = char;
    }
    return true;
}

pub fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

pub fn runProcess(allocator: Allocator, args: []const []const u8, dir: ?std.fs.Dir) !std.process.Child.RunResult {
    var child = std.process.Child.init(args, allocator);
    child.cwd_dir = dir orelse null;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(allocator);
    var stderr = std.ArrayList(u8).init(allocator);
    errdefer {
        stdout.deinit();
        stderr.deinit();
    }
    try child.spawn();
    try child.collectOutput(&stdout, &stderr, 4096 * 4);
    return .{
        .term = try child.wait(),
        .stdout = try stdout.toOwnedSlice(),
        .stderr = try stderr.toOwnedSlice(),
    };
}

test "valid linux paths" {
    try std.testing.expect(validLinuxPath("basic"));
    try std.testing.expect(validLinuxPath("basic/"));
    try std.testing.expect(validLinuxPath("/basic/"));
    try std.testing.expect(validLinuxPath("/home/cristian/.config/nvim"));
    try std.testing.expect(validLinuxPath("/home/cristian-2/.config/nvim"));
    try std.testing.expect(validLinuxPath("/home/cristian-_2/.config/nvim"));
}

test "not valid linux paths" {
    try std.testing.expect(!validLinuxPath("*!lp"));
    try std.testing.expect(!validLinuxPath("lp=.'"));
}
