const pow = @import("std").math.pow;

pub const defines = @This();

pub const max_config_file_size = u32;

pub const BYTE_TO_GB_FACTOR = pow(usize, 10, 9);

pub const EXCLUDE_DIRS = [_][]const u8{".git"};
