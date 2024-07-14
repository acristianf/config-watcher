const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "config-watcher",
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
    });
    b.installArtifact(exe);
}
