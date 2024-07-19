const std = @import("std");
const env_parser = @import("env-parser.zig");
const utils = @import("utils.zig").utils;
const fsmanip = @import("fsmanip.zig").fsmanip;
const s_config = @import("s_config.zig").s_config;

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
            _ = real_file_path;
            const structure = args.next() orelse {
                std.log.err(HELP_ADD_FILE, .{});
                return;
            };
            if (!utils.validPath(structure)) {
                return std.log.err("Not a valid path passed down as a structure", .{});
            }
            const dir = try fsmanip.mkStructure(config, structure);
            _ = dir;
            return;
        }
    }
}
