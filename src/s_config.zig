const std = @import("std");
const pow = @import("std").math.pow;
const Allocator = @import("std").mem.Allocator;
const utils = @import("utils.zig").utils;
const WatcherConfErrors = @import("r_errors.zig").r_errors.WatcherConfErrors;
const GeneralErrors = @import("r_errors.zig").r_errors.GeneralErrors;
const defines = @import("defines.zig").defines;

pub const s_config = @This();

const MAX_KEY_LEN = 512;
const MAX_VALUE_LEN = std.fs.max_path_bytes - MAX_KEY_LEN;

pub const WatcherConfig = struct {
    allocator: Allocator,
    home_dir: []const u8,
    config_file_path: []const u8,

    // Configuration specific
    folder: ?[]const u8,
    remote: ?[]const u8,

    const config_path_dir = "/.watcher/";
    const config_filename = "watcher.env";

    const Self = @This();

    pub fn init(allocator: Allocator) !WatcherConfig {
        const home_dir = std.posix.getenv("HOME") orelse return WatcherConfErrors.HomeEnvNotSet;

        const full_config_path_dir = try utils.concat(allocator, home_dir, config_path_dir);
        defer allocator.free(full_config_path_dir);

        std.fs.makeDirAbsolute(full_config_path_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };

        // Load config file
        const cfp = try utils.concat(allocator, home_dir, Self.config_path_dir ++ Self.config_filename);

        var config_map = std.StringHashMap([]const u8).init(allocator);
        defer config_map.deinit();

        const file = try std.fs.openFileAbsolute(cfp, .{});
        defer file.close();

        try parseConfigFile(allocator, &config_map, &file);

        var f = config_map.get("folder") orelse null;

        if (f) |setted_folder| {
            if (setted_folder[setted_folder.len - 1] != '/') {
                f = try utils.concat(allocator, setted_folder, "/");
            }
        }

        return .{
            .folder = f,
            .remote = config_map.get("remote") orelse null,
            .home_dir = home_dir,
            .config_file_path = cfp,
            .allocator = allocator,
        };
    }

    pub fn update(self: *WatcherConfig) !void {
        var buf: [std.fs.max_path_bytes - 1:0]u8 = undefined;

        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const fbaa = fba.allocator();

        const file = try std.fs.createFileAbsolute(self.config_file_path, .{ .truncate = true });

        if (self.folder) |folder| {
            _ = try file.write(try std.mem.concat(fbaa, u8, &.{ "folder=", folder, "\n" }));
            fba.reset();
        }

        if (self.remote) |remote| {
            _ = try file.write(try std.mem.concat(fbaa, u8, &.{ "remote=", remote, "\n" }));
            fba.reset();
        }
    }

    pub fn setupRemote(self: *WatcherConfig, remote: []const u8) !void {
        // TODO: Make this check better
        if (std.mem.eql(u8, remote[0..5], "http:") or std.mem.eql(u8, remote[0..6], "https:")) {
            std.log.err("don't support http/https git remote", .{});
            return GeneralErrors.GitError;
        }

        if (self.folder == null) {
            std.log.err("couldn't find config folder, did you set it up?", .{});
            return error.ContainerFolderNotSet;
        }

        var dir = try std.fs.openDirAbsolute(self.folder.?, .{});
        defer dir.close();
        try dir.deleteTree(".git");

        const echo_file = try utils.runProcess(self.allocator, &.{ "touch", "README.md" }, dir);
        if (echo_file.term.Exited != 0) {
            std.log.err("couldn't echo into README.md", .{});
            std.log.err("ECHO OUTPUT: \n{s}", .{echo_file.stderr});
            return;
        }

        const result_init = try utils.runProcess(self.allocator, &.{ "git", "init" }, dir);
        if (result_init.term.Exited != 0) {
            return GeneralErrors.GitError;
        }
        std.log.info("{s}", .{result_init.stdout});

        const first_add = try utils.runProcess(self.allocator, &.{ "git", "add", "README.md" }, dir);
        _ = first_add;

        const first_commit = try utils.runProcess(self.allocator, &.{ "git", "commit", "-m", "\"watcher first commit\"" }, dir);
        if (first_commit.term.Exited != 0) {
            std.log.err("couldn't run first commit", .{});
            return GeneralErrors.GitError;
        }

        const result_setup_main = try utils.runProcess(self.allocator, &.{ "git", "branch", "-M", "main" }, dir);
        if (result_setup_main.term.Exited != 0) {
            std.log.err("couldn't setup main branch to {s}", .{remote});
            std.log.err("GIT OUTPUT: \n{s}", .{result_setup_main.stderr});
            return GeneralErrors.GitError;
        }

        const result_add_origin = try utils.runProcess(self.allocator, &.{ "git", "remote", "add", "origin", remote }, dir);
        if (result_add_origin.term.Exited != 0) {
            std.log.err("couldn't setup remote to {s}", .{remote});
            std.log.err("GIT OUTPUT: \n{s}", .{result_add_origin.stderr});
            return GeneralErrors.GitError;
        }
        std.log.info("Setted up remote to {s}\n", .{remote});

        const result_setup_upstream = try utils.runProcess(self.allocator, &.{ "git", "push", "-u", "origin", "main" }, dir);
        if (result_setup_upstream.term.Exited != 0) {
            std.log.err("couldn't setup upstream branch", .{});
            std.log.err("GIT OUTPUT: \n{s}", .{result_setup_upstream.stderr});
            return GeneralErrors.GitError;
        }

        std.log.info("to upload your configurations run the --push flag", .{});
    }

    fn parseConfigFile(
        allocator: std.mem.Allocator,
        out_map: *std.StringHashMap([]const u8),
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
                const line_end = std.mem.indexOfAny(u8, buf[start + pos .. end], &.{ '\n', 0, '\r' }) orelse break;
                var key: [MAX_KEY_LEN:0]u8 = undefined;
                var value: [MAX_VALUE_LEN:0]u8 = undefined;
                if (pos > MAX_KEY_LEN) return error.ConfigKeyTooLong;
                if (line_end - 1 > MAX_VALUE_LEN) return error.ConfigValueTooLong;
                @memcpy(key[0..pos], buf[start .. start + pos]);
                @memcpy(value[0 .. line_end - 1], buf[start + pos + 1 .. start + pos + line_end]);
                const off: u32 = @truncate(line_end + pos);
                try out_map.put(
                    try allocator.dupe(u8, key[0..pos]),
                    try allocator.dupe(u8, value[0 .. line_end - 1]),
                );
                start += off;
            }
        }
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

test "Detect Leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    defer _ = gpa.detectLeaks();

    var arena = std.heap.ArenaAllocator.init(gpaa);
    defer arena.deinit();

    const aa = arena.allocator();
    _ = try WatcherConfig.init(aa);
}
