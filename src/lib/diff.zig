const std = @import("std");

pub const Point = struct {
    const Self = @This();
    x: isize,
    y: isize,

    pub fn zero() Self {
        return .{
            .x = 0,
            .y = 0,
        };
    }

    pub fn eql(self: *const Self, b: Self) bool {
        return self.x == b.x and self.y == b.y;
    }
};

// TODO: Handle more robustly
// Not robust
fn match(comptime T: type, a: T, b: T) bool {
    const typeinfo = @typeInfo(T);
    switch (typeinfo) {
        .Pointer => return std.mem.eql(typeinfo.Pointer.child, a, b),
        else => return a == b,
    }
}

pub fn MyersDiff(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        a: []const T,
        b: []const T,
        vf: []usize,
        vb: []usize,
        v_mid: isize,

        pub fn init(allocator: std.mem.Allocator, f1: []const T, f2: []const T) !Self {
            const max_diagonals: usize = 2 * (f1.len + f2.len) + 1;
            const maxd2: isize = @intCast(try std.math.divCeil(isize, @intCast(max_diagonals), 2));

            const o = Self{
                .allocator = allocator,
                .a = f1,
                .b = f2,
                .vf = try allocator.alloc(usize, max_diagonals),
                .vb = try allocator.alloc(usize, max_diagonals),
                .v_mid = maxd2,
            };

            // if (f1.len < f2.len) {
            //     o.a = f2;
            //     o.b = f1;
            // }

            return o;
        }

        pub fn distance(self: *Self) !usize {
            const size: usize = self.a.len + self.b.len;
            if (size == 0) return 0;

            const max: isize = @intCast(try std.math.divCeil(usize, size, 2));

            @memset(self.vf, 0);
            self.vf[@as(usize, @intCast(self.v_mid)) + 1] = 0;

            var d: isize = 0;
            var r: usize = 0;
            outer: for (0..@intCast(max)) |idx| {
                d = @intCast(idx);

                var k: isize = -d;
                while (k <= d) : (k += 2) {
                    var x: isize = 0;
                    const off_k: usize = @intCast(k + self.v_mid);
                    if (k == -d or k != d and self.vf[off_k - 1] < self.vf[off_k + 1]) {
                        x = @intCast(self.vf[off_k + 1]);
                    } else {
                        x = @intCast(self.vf[off_k - 1] + 1);
                    }
                    var y: isize = x - k;

                    while (x < self.a.len and y < self.b.len and match(T, self.a[@intCast(x)], self.b[@intCast(y)])) {
                        x += 1;
                        y += 1;
                    }

                    self.vf[off_k] = @intCast(x);

                    if (x >= self.a.len and y >= self.b.len) {
                        r = idx;
                        break :outer;
                    }
                }
            }
            return r;
        }

        fn midpoint(self: *Self, off: Point, limit: Point) !?[2]Point {
            const width: isize = limit.x - off.x;
            const height: isize = limit.y - off.y;

            const size: isize = width + height;
            if (size == 0) return null;

            const max: isize = @intCast(try std.math.divCeil(isize, size, 2));

            @memset(self.vf, 0);
            @memset(self.vb, 0);
            self.vf[@as(usize, @intCast(self.v_mid)) + 1] = @intCast(off.x); // Start with left value
            self.vb[@as(usize, @intCast(self.v_mid)) + 1] = @intCast(limit.y); // Start with bottom value

            const delta: isize = width - height;

            const odd: bool = (delta & 1) == 1;

            var d: isize = 0;
            for (0..@intCast(max)) |idx| {
                d = @intCast(idx);

                var k: isize = -d;
                var px: isize = 0;
                var py: isize = 0;
                while (k <= d) : (k += 2) {
                    const c: isize = k - delta;

                    var x: isize = 0;
                    const off_k: usize = @intCast(k + self.v_mid);
                    if (k == -d or k != d and self.vf[off_k - 1] < self.vf[off_k + 1]) {
                        x = @intCast(self.vf[off_k + 1]);
                        px = x;
                    } else {
                        px = @intCast(self.vf[off_k - 1]);
                        x = px + 1;
                    }
                    var y: isize = off.y + x - off.x - k;
                    py = if (d == 0 or x != px) y else y - 1;

                    while (x < limit.x and y < limit.y and match(T, self.a[@intCast(x)], self.b[@intCast(y)])) {
                        x += 1;
                        y += 1;
                    }

                    self.vf[off_k] = @intCast(x);

                    const off_c: usize = @intCast(c + self.v_mid);
                    if (odd and c >= -(d - 1) and c <= d - 1 and y >= self.vb[off_c]) {
                        return .{
                            .{
                                .x = px,
                                .y = py,
                            },
                            .{
                                .x = x,
                                .y = y,
                            },
                        };
                    }
                }
                var c: isize = -d;
                while (c <= d) : (c += 2) {
                    const in_k = c + delta;

                    const off_c: usize = @intCast(c + self.v_mid);
                    var y: isize = 0;
                    if (c == -d or c != d and self.vb[off_c - 1] > self.vb[off_c + 1]) {
                        y = @intCast(self.vb[off_c + 1]);
                        py = y;
                    } else {
                        py = @intCast(self.vb[off_c - 1]);
                        y = py - 1;
                    }

                    var x: isize = off.x + (y - off.y) + in_k;
                    px = if (d == 0 or y != py) x else x + 1;

                    while (x > off.x and y > off.y and match(T, self.a[@intCast(x - 1)], self.b[@intCast(y - 1)])) {
                        x -= 1;
                        y -= 1;
                    }

                    self.vb[off_c] = @intCast(y);

                    const off_k: usize = @intCast(in_k + self.v_mid);
                    if (!odd and in_k >= -d and in_k <= d and x <= self.vf[off_k]) {
                        return .{
                            .{
                                .x = x,
                                .y = y,
                            },
                            .{
                                .x = px,
                                .y = py,
                            },
                        };
                    }
                }
            }
            return null;
        }

        fn findPath(self: *Self, off: Point, limit: Point, array: *std.ArrayList([2]Point)) !void {
            const snake_opt = try self.midpoint(off, limit);
            const snake = snake_opt orelse {
                if (!off.eql(limit)) {
                    try array.append(.{ off, limit });
                }
                return;
            };

            const start = snake[0];
            const finish = snake[1];

            try self.findPath(off, .{ .x = start.x, .y = start.y }, array);
            try array.append(snake);
            try self.findPath(.{ .x = finish.x, .y = finish.y }, limit, array);
        }

        pub fn diff(self: *Self, arr: *std.ArrayList([2]Point)) !void {
            try findPath(self, Point.zero(), .{ .x = @intCast(self.a.len), .y = @intCast(self.b.len) }, arr);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.vf);
            self.allocator.free(self.vb);
        }
    };
}

test "diff" {
    const allo = std.testing.allocator;
    var array = std.ArrayList([2]Point).init(allo);
    defer array.deinit();

    var m_d = try MyersDiff(u8).init(allo, "abcabba", "cbabac");
    defer m_d.deinit();
    try m_d.diff(&array);

    try std.testing.expect(array.items[0][0].eql(.{ .x = 0, .y = 0 }));
    try std.testing.expect(array.items[0][1].eql(.{ .x = 1, .y = 0 }));
    try std.testing.expect(array.items[1][0].eql(.{ .x = 1, .y = 0 }));
    try std.testing.expect(array.items[1][1].eql(.{ .x = 2, .y = 0 }));
    try std.testing.expect(array.items[2][0].eql(.{ .x = 2, .y = 0 }));
    try std.testing.expect(array.items[2][1].eql(.{ .x = 3, .y = 1 }));
    try std.testing.expect(array.items[3][0].eql(.{ .x = 3, .y = 1 }));
    try std.testing.expect(array.items[3][1].eql(.{ .x = 5, .y = 4 }));
    try std.testing.expect(array.items[4][0].eql(.{ .x = 5, .y = 4 }));
    try std.testing.expect(array.items[4][1].eql(.{ .x = 6, .y = 4 }));
    try std.testing.expect(array.items[5][0].eql(.{ .x = 6, .y = 4 }));
    try std.testing.expect(array.items[5][1].eql(.{ .x = 7, .y = 6 }));
}

test "distance" {
    const allo = std.testing.allocator;

    var m_d = try MyersDiff(u8).init(allo, "abcabba", "cbabac");
    defer m_d.deinit();

    try std.testing.expect((try m_d.distance()) == 5);
}

test "eql" {
    const allo = std.testing.allocator;
    var m_d = try MyersDiff(u8).init(allo, "aaa", "aaa");
    defer m_d.deinit();

    var array = std.ArrayList([2]Point).init(allo);
    defer array.deinit();

    try m_d.diff(&array);

    try std.testing.expect(array.items.len == 1);
}
