const std = @import("std");
const builtin = @import("builtin");

pub const Windows = struct {
    const codepage = enum(c_uint) { UTF8 = 65001 };
    pub extern "user32" fn SetConsoleCP(in: codepage) void;
    pub extern "user32" fn SetConsoleOutputCP(in: codepage) void;
};

pub fn init() void {
    if (builtin.target.os.tag == .windows) {
        Windows.SetConsoleOutputCP(.UTF8);
    }
}

fn log(comptime label: []const u8, output: anytype, comptime fmt: []const u8, args: anytype) !void {
    try output.print("[{s}] " ++ fmt ++ "\n", .{label} ++ args);
}

pub fn usage(comptime fmt: []const u8, args: anytype) void {
    log("USAGE", std.io.getStdOut().writer(), fmt, args) catch unreachable;
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log("INFO", std.io.getStdOut().writer(), fmt, args) catch unreachable;
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log("DEBUG", std.io.getStdErr().writer(), fmt, args) catch unreachable;
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    log("WARN", std.io.getStdErr().writer(), fmt, args) catch unreachable;
}

pub fn fatal(comptime fmt: []const u8, args: anytype) void {
    log("ERROR", std.io.getStdErr().writer(), fmt, args) catch unreachable;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch unreachable;
}
