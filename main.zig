const std = @import("std");
const utils = @import("utils.zig").utils;
const fsmanip = @import("fsmanip.zig").fsmanip;
const s_config = @import("s_config.zig").s_config;
const WatcherConfErrors = @import("r_errors.zig").WatcherConfErrors;

const Allocator = std.mem.Allocator;

const MAX_LINE_SIZE = 256 + std.fs.max_path_bytes;

const HELP_ADD_FILE =
    \\config-watcher --add-file <file> <structure>
    \\      <file> can be relative or absolute path to a file you want to save in your setted folder
    \\      <structure> folder structure where to save file ex. .config/nvim
;

const SET_FOLDER_HELP =
    \\config-watcher --add-folder <folder>
    \\      Sets the folder where to save your configs. This config is saved inside ~/.watcher/watcher.env
;

pub fn main() !void {
    const HOME_DIR = std.posix.getenv("HOME") orelse return error.HomeEnvNotSet;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaa = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpaa);
    const aa = arena.allocator();
    defer arena.deinit();

    const config = try s_config.parseConfig(aa);

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
            const watcher = utils.concat(aa, HOME_DIR, "/.watcher") catch |err| {
                std.log.err("{!} \n", .{err});
                return;
            };
            std.fs.makeDirAbsolute(watcher) catch |err| {
                switch (err) {
                    error.PathAlreadyExists => {},
                    else => {
                        std.log.err("Unexpected error creating '.watcher' folder on home. Error: {!} \n", .{err});
                        return;
                    },
                }
            };
            var watcher_dir = std.fs.openDirAbsolute(watcher, .{}) catch |err| {
                switch (err) {
                    error.AccessDenied => std.log.err("Access Denied trying to open folder '{s}' \n", .{watcher}),
                    else => std.log.err("Unexpected error. Error: {!} \n", .{err}),
                }
                return;
            };
            defer watcher_dir.close();
            var watcher_file = watcher_dir.createFile("watcher.env", .{ .truncate = false }) catch |err| {
                switch (err) {
                    error.AccessDenied => std.log.err("Access Denied trying to create/open 'watcher.env' \n", .{}),
                    else => std.log.err("Unexpected error trying to create/open 'watcher.env'. Error: {!} \n", .{err}),
                }
                return;
            };
            defer watcher_file.close();
            try watcher_file.seekFromEnd(0);
            const folderconfig = try utils.concat(aa, "folder=", realpath);
            _ = try watcher_file.write(folderconfig);
            _ = try watcher_file.write("\n");
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
            const dest_path = try fsmanip.createStructurePath(aa, setted_folder.value, s_w_filename);
            var dest_dir = try fsmanip.mkStructure(setted_folder.value, structure);
            defer dest_dir.close();

            try source_dir.copyFile(real_file_path, dest_dir, dest_path, .{});

            std.log.info("file added to {s}\n", .{dest_path});

            return;
        }
    }
}
