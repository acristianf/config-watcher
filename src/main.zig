const std = @import("std");
const utils = @import("utils.zig").utils;
const fsmanip = @import("fsmanip.zig").fsmanip;
const s_config = @import("s_config.zig").s_config;
const WatcherConfErrors = @import("r_errors.zig").WatcherConfErrors;
const GeneralErrors = @import("r_errors.zig").GeneralErrors;

const Allocator = std.mem.Allocator;

const MAX_LINE_SIZE = 256 + std.fs.max_path_bytes;

const HELP_ADD_FILE =
    \\config-watcher --add-file <file> <structure>
    \\      <file> can be relative or absolute path to a file you want to save in your setted folder
    \\      <structure> folder structure where to save file ex. .config/nvim
;

const SET_FOLDER_HELP =
    \\config-watcher --set-folder <folder>
    \\      Sets the folder where to save your configs. This config is saved inside ~/.watcher/watcher.env
;

const SET_REMOTE_HELP =
    \\config-watcher --set-remote <remote>
    \\      Sets the remote repository where to upload your configs. This config is saved inside ~/.watcher/watcher.env
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaa);
    const aa = arena.allocator();
    defer arena.deinit();

    var config = try s_config.WatcherConfig.init(aa);

    var args = std.process.args();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--set-folder")) {
            const path = args.next() orelse {
                std.log.err(SET_FOLDER_HELP, .{});
                return;
            };
            var realpathbuf: [std.fs.max_path_bytes:0]u8 = undefined;
            const realpath = std.fs.realpath(path, &realpathbuf) catch |err| {
                std.log.err("Couldn't read path '{s}'. Error: {!} \n", .{ path, err });
                return;
            };
            config.folder = realpath;
            try config.update();
        } else if (std.mem.eql(u8, arg, "--add-file")) {
            const setted_folder = config.folder orelse return WatcherConfErrors.ContainerFolderNotSet;

            const file_path = args.next() orelse {
                std.log.err(HELP_ADD_FILE, .{});
                return;
            };

            var b: [std.fs.max_path_bytes:0]u8 = undefined;
            const real_file_path = std.fs.realpath(file_path, &b) catch |err| {
                switch (err) {
                    error.FileNotFound => std.log.err("File '{s}' not found\n", .{file_path}),
                    else => std.log.err("Unexpected error {!}\n", .{err}),
                }
                return;
            };

            // Check if we can open the file
            const file_check = try std.fs.openFileAbsolute(real_file_path, .{});
            file_check.close();

            const last_slash = std.mem.lastIndexOfScalar(u8, real_file_path, '/');
            const filename = if (last_slash) |pos| file_path[pos..] else file_path;

            const s = args.next() orelse {
                std.log.err(HELP_ADD_FILE, .{});
                return;
            };
            const structure = if (s[s.len - 1] != '/') try utils.concat(aa, s, "/") else s;

            if (!utils.validLinuxPath(structure)) {
                return std.log.err("Not a valid path passed down as a structure", .{});
            }

            const source_dir_path = real_file_path[0..last_slash.?];
            var source_dir = try std.fs.openDirAbsolute(source_dir_path, .{});
            defer source_dir.close();

            const s_w_filename = try utils.concat(aa, structure, filename);
            const dest_path = try fsmanip.createStructurePath(aa, setted_folder, s_w_filename);
            var dest_dir = try fsmanip.mkStructure(setted_folder, structure);
            defer dest_dir.close();

            try source_dir.copyFile(real_file_path, dest_dir, dest_path, .{});

            std.log.info("file added to {s}\n", .{dest_path});
        } else if (std.mem.eql(u8, arg, "--set-remote")) {
            const remote: []const u8 = args.next() orelse {
                std.log.err(SET_REMOTE_HELP, .{});
                return;
            };
            try config.setupRemote(remote);
        } else if (std.mem.eql(u8, arg, "--push")) {
            // TODO: extract this git logic
            if (config.folder == null) {
                std.log.warn("configurations folder not set, can't push without a configs folder!\n", .{});
                return WatcherConfErrors.ContainerFolderNotSet;
            }
            var configs_folder = try std.fs.openDirAbsolute(config.folder.?, .{});
            defer configs_folder.close();
            const result_add = try utils.runProcess(aa, &.{ "git", "add", "." }, configs_folder);
            if (result_add.term.Exited != 0) {
                std.log.err("Couldn't 'git add'. Is there a problem with the git setup inside the folder? run --set-remote again", .{});
                return GeneralErrors.GitError;
            }

            const result_commit = try utils.runProcess(aa, &.{ "git", "commit", "-m", "watcher push" }, configs_folder);
            if (result_commit.term.Exited != 0) {
                std.log.err("Couldn't create commit", .{});
                std.log.err("GIT OUTPUT:\n{s}", .{result_commit.stdout});
                return GeneralErrors.GitError;
            }

            const result_push = try utils.runProcess(aa, &.{ "git", "push" }, configs_folder);
            if (result_push.term.Exited != 0) {
                std.log.err("Couldn't push to remote", .{});
                std.log.err("GIT OUTPUT: \n{s}\n", .{result_push.stderr});
                return GeneralErrors.GitError;
            }
            std.log.info("{s}\n", .{result_push.stdout});
        }
    }
}
