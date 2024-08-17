const std = @import("std");
const utils = @import("utils.zig").utils;
const GeneralErrors = @import("r_errors.zig").GeneralErrors;

pub const git_wrapper = @This();

pub const Git = struct {
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, absolute_path: []const u8) !Git {
        const d = try std.fs.openDirAbsolute(absolute_path, .{});
        return .{
            .allocator = allocator,
            .dir = d,
        };
    }

    pub fn free(self: *Git, result: *std.process.Child.RunResult) void {
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }

    pub fn add(self: *Git, files: ?[]const u8) !void {
        var result = try utils.runProcess(self.allocator, &.{ "git", "add", files orelse "." }, self.dir);
        defer self.free(&result);
        if (result.term.Exited != 0) {
            std.log.err("Couldn't 'git add'. Is there a problem with the git setup inside the folder? run --set-remote again", .{});
            return GeneralErrors.GitError;
        }
    }

    pub fn commit(self: *Git, msg: ?[]const u8) !u8 {
        var check = try utils.runProcess(self.allocator, &.{ "git", "diff", "--quiet" }, self.dir);
        defer self.free(&check);
        if (check.term.Exited != 1) {
            std.log.info("no changes to sync", .{});
            return 1;
        }
        var result = try utils.runProcess(self.allocator, &.{ "git", "commit", "-m", msg orelse "watcher sync" }, self.dir);
        defer self.free(&result);
        if (result.term.Exited != 0) {
            std.log.err("Couldn't create commit", .{});
            std.log.err("GIT OUTPUT:\n{s}", .{result.stdout});
            return GeneralErrors.GitError;
        }
        return 0;
    }

    pub fn push(self: *Git) !void {
        var result = try utils.runProcess(self.allocator, &.{ "git", "push" }, self.dir);
        defer self.free(&result);
        if (result.term.Exited != 0) {
            std.log.err("Couldn't push to remote", .{});
            std.log.err("GIT OUTPUT: \n{s}", .{result.stderr});
            return GeneralErrors.GitError;
        }
        std.log.info("synced correctly", .{});
    }

    pub fn setupRemote(self: *Git, remote: []const u8) !void {
        // TODO: Make this check better
        if (std.mem.eql(u8, remote[0..5], "http:") or std.mem.eql(u8, remote[0..6], "https:")) {
            std.log.err("don't support http/https git remote", .{});
            return GeneralErrors.GitError;
        }

        try self.dir.deleteTree(".git");

        var touch_file = try utils.runProcess(self.allocator, &.{ "touch", "README.md" }, self.dir);
        defer self.free(&touch_file);
        if (touch_file.term.Exited != 0) {
            std.log.err("couldn't touch README.md", .{});
            std.log.err("TOUCH OUTPUT: \n{s}", .{touch_file.stderr});
            return;
        }

        var result_init = try utils.runProcess(self.allocator, &.{ "git", "init" }, self.dir);
        defer self.free(&result_init);
        if (result_init.term.Exited != 0) {
            return GeneralErrors.GitError;
        }
        std.log.info("{s}", .{result_init.stdout});

        try self.add(null);
        _ = try self.commit("watcher init");

        var result_setup_main = try utils.runProcess(self.allocator, &.{ "git", "branch", "-M", "main" }, self.dir);
        defer self.free(&result_setup_main);
        if (result_setup_main.term.Exited != 0) {
            std.log.err("couldn't setup main branch to {s}", .{remote});
            std.log.err("GIT OUTPUT: \n{s}", .{result_setup_main.stderr});
            return GeneralErrors.GitError;
        }

        var result_add_origin = try utils.runProcess(self.allocator, &.{ "git", "remote", "add", "origin", remote }, self.dir);
        defer self.free(&result_add_origin);
        if (result_add_origin.term.Exited != 0) {
            std.log.err("couldn't setup remote to {s}", .{remote});
            std.log.err("GIT OUTPUT: \n{s}", .{result_add_origin.stderr});
            return GeneralErrors.GitError;
        }
        std.log.info("container up remote to {s}\n", .{remote});

        var result_fetch = try utils.runProcess(self.allocator, &.{ "git", "fetch" }, self.dir);
        defer self.free(&result_fetch);
        if (result_fetch.term.Exited != 0) {
            std.log.err("couldn't fetch objects and refs from repository", .{});
            std.log.err("GIT OUTPUT: \n{s}", .{result_fetch.stderr});
            return GeneralErrors.GitError;
        }

        var result_pull = try utils.runProcess(self.allocator, &.{ "git", "pull", "--rebase", "origin", "main" }, self.dir);
        defer self.free(&result_pull);
        if (result_pull.term.Exited != 0) {
            std.log.err("couldn't pull --rebase possible repository refs", .{});
            std.log.err("GIT OUTPUT: \n{s}", .{result_pull.stderr});
            return GeneralErrors.GitError;
        }

        var result_setup_upstream = try utils.runProcess(self.allocator, &.{ "git", "push", "-u", "origin", "main" }, self.dir);
        defer self.free(&result_setup_upstream);
        if (result_setup_upstream.term.Exited != 0) {
            std.log.err("couldn't setup upstream branch", .{});
            std.log.err("GIT OUTPUT: \n{s}", .{result_setup_upstream.stderr});
            return GeneralErrors.GitError;
        }

        std.log.info("successfully set remote, to upload your configurations run the --sync flag", .{});
    }

    pub fn deinit(self: *Git) void {
        self.dir.close();
    }
};
