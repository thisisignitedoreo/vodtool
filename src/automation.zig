const std = @import("std");

pub const Windows = struct {
    pub const InputType = enum(u32) {
        Mouse = 0,
        Keyboard = 1,
        Hardware = 2,
    };
    pub const Input = extern struct {
        kind: InputType,
        data: extern union {
            mi: extern struct {
                dx: c_long,
                dy: c_long,
                mouseData: u32,
                dwFlags: u32,
                time: u32,
                dwExtraInfo: [*c]c_ulong,
            },
            ki: extern struct {
                wVk: u16,
                wScan: u16,
                dwFlags: u32,
                time: u32,
                dwExtraInfo: [*c]c_ulong,
            },
            hi: extern struct {
                uMsg: u32,
                wParamL: u16,
                wParamH: u16,
            },
        },
    };
    extern "user32" fn SendInput(c: c_uint, w: [*c]Input, s: c_int) c_uint;

    extern "user32" fn GetCursorPos(p: *Mouse.Point) bool;

    extern "user32" fn OpenClipboard(c: ?*anyopaque) bool;
    extern "user32" fn CloseClipboard() bool;
    extern "user32" fn EmptyClipboard() bool;
    extern "user32" fn SetClipboardData(format: c_uint, mem: ?*anyopaque) ?*anyopaque;

    extern "user32" fn GlobalAlloc(flags: c_uint, bytes: usize) ?*anyopaque;
    extern "user32" fn GlobalFree(c: ?*anyopaque) ?*anyopaque;
    extern "user32" fn GlobalLock(c: ?*anyopaque) ?*anyopaque;
    extern "user32" fn GlobalUnlock(c: ?*anyopaque) bool;

    extern "user32" fn SetForegroundWindow(w: ?*anyopaque) bool;
    extern "user32" fn GetForegroundWindow() ?*anyopaque;
    extern "user32" fn GetWindowRect(w: ?*anyopaque, r: *Window.Rectangle) bool;
    extern "user32" fn GetWindow(w: ?*anyopaque, r: c_uint) ?*anyopaque;
    extern "user32" fn GetWindowTextLengthA(w: ?*anyopaque) c_int;
    extern "user32" fn GetWindowTextA(w: ?*anyopaque, r: [*]u8, c: c_int) c_int;
    extern "user32" fn WindowFromPoint(p: Mouse.Point) ?*anyopaque;

    extern "user32" fn Sleep(delay: u32) void;

    extern "user32" fn GetLastError() u32;
};

pub fn sendInput(inputs: []const Windows.Input) !void {
    const count = Windows.SendInput(@as(c_uint, @intCast(inputs.len)), @as([*c]Windows.Input, @constCast(inputs.ptr)), @sizeOf(Windows.Input));
    if (count != inputs.len) return error.FunctionFailed;
}

pub const Mouse = struct {
    pub fn moveRelative(x: i64, y: i64) !void {
        try sendInput(&.{.{
            .kind = .Mouse,
            .data = .{
                .mi = .{
                    .dx = @as(c_long, @intCast(x)),
                    .dy = @as(c_long, @intCast(y)),
                    .mouseData = 0,
                    .dwFlags = 1,
                    .time = 0,
                    .dwExtraInfo = 0,
                },
            },
        }});
    }

    pub fn move(x: i64, y: i64) !void {
        try sendInput(&.{
            .{
                .kind = .Mouse,
                .data = .{
                    .mi = .{
                        .dx = 0,
                        .dy = 0,
                        .mouseData = 0,
                        .dwFlags = 0x8001,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
            .{
                .kind = .Mouse,
                .data = .{
                    .mi = .{
                        .dx = @as(c_long, @intCast(x)),
                        .dy = @as(c_long, @intCast(y)),
                        .mouseData = 0,
                        .dwFlags = 1,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
        });
    }

    pub const MouseButton = enum { Left, Right, Middle };
    pub fn click(btn: MouseButton) !void {
        try sendInput(&.{
            .{
                .kind = .Mouse,
                .data = .{
                    .mi = .{
                        .dx = 0,
                        .dy = 0,
                        .mouseData = 0,
                        .dwFlags = switch (btn) {
                            .Left => 2,
                            .Right => 8,
                            .Middle => 32,
                        },
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
            .{
                .kind = .Mouse,
                .data = .{
                    .mi = .{
                        .dx = 0,
                        .dy = 0,
                        .mouseData = 0,
                        .dwFlags = switch (btn) {
                            .Left => 4,
                            .Right => 16,
                            .Middle => 64,
                        },
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
        });
    }

    pub fn buttonDown(btn: MouseButton) !void {
        try sendInput(&.{.{
            .kind = .Mouse,
            .data = .{
                .mi = .{
                    .dx = 0,
                    .dy = 0,
                    .mouseData = 0,
                    .dwFlags = switch (btn) {
                        .Left => 2,
                        .Right => 8,
                        .Middle => 32,
                    },
                    .time = 0,
                    .dwExtraInfo = 0,
                },
            },
        }});
    }

    pub fn buttonUp(btn: MouseButton) !void {
        try sendInput(&.{.{
            .kind = .Mouse,
            .data = .{
                .mi = .{
                    .dx = 0,
                    .dy = 0,
                    .mouseData = 0,
                    .dwFlags = switch (btn) {
                        .Left => 4,
                        .Right => 16,
                        .Middle => 64,
                    },
                    .time = 0,
                    .dwExtraInfo = 0,
                },
            },
        }});
    }

    pub const Point = extern struct {
        x: c_long,
        y: c_long,
    };

    pub fn getPosition() !Point {
        var p: Point = undefined;
        if (Windows.GetCursorPos(&p) == false) return error.FunctionFailed;
        return p;
    }
};

pub const Keyboard = struct {
    pub const VK = enum(u16) {
        Enter = 0x0D,
        LCtrl = 0x11,
        LWin = 0x5B,
        RWin = 0x5C,
        LShift = 0xA0,
        RShift = 0xA1,
        RCtrl = 0xA3,
        A = 'A',
        B = 'B',
        C = 'C',
        D = 'D',
        E = 'E',
        F = 'F',
        G = 'G',
        H = 'H',
        I = 'I',
        J = 'J',
        K = 'K',
        L = 'L',
        M = 'M',
        N = 'N',
        O = 'O',
        P = 'P',
        Q = 'Q',
        R = 'R',
        S = 'S',
        T = 'T',
        U = 'U',
        V = 'V',
        W = 'W',
        X = 'X',
        Y = 'Y',
        Z = 'Z',
    };

    pub fn keyDown(vk: VK) !void {
        try sendInput(&.{
            .{
                .kind = .Keyboard,
                .data = .{
                    .ki = .{
                        .wVk = @as(u16, @intFromEnum(vk)),
                        .wScan = 0,
                        .dwFlags = 0,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
        });
    }

    pub fn keyUp(vk: VK) !void {
        try sendInput(&.{
            .{
                .kind = .Keyboard,
                .data = .{
                    .ki = .{
                        .wVk = @as(u16, @intFromEnum(vk)),
                        .wScan = 0,
                        .dwFlags = 2,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
        });
    }

    pub fn scancode(scan: u16) !void {
        try sendInput(&.{
            .{
                .kind = .Keyboard,
                .data = .{
                    .ki = .{
                        .wVk = 0,
                        .wScan = scan,
                        .dwFlags = 4,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
            .{
                .kind = .Keyboard,
                .data = .{
                    .ki = .{
                        .wVk = 0,
                        .wScan = scan,
                        .dwFlags = 6,
                        .time = 0,
                        .dwExtraInfo = 0,
                    },
                },
            },
        });
    }

    pub fn key(vk: VK) !void {
        try keyDown(vk);
        try keyUp(vk);
    }

    pub fn keyCombo(vk: []const VK) !void {
        for (0..vk.len) |i| {
            try keyDown(vk[i]);
        }
        var i: usize = vk.len;
        while (i > 0) {
            i -= 1;
            try keyUp(vk[i]);
        }
    }

    pub fn keySequence(vk: []const VK) !void {
        for (0..vk.len) |i| {
            try key(vk[i]);
        }
    }

    pub fn char(codepoint: u21) !void {
        if (codepoint < 0x10000) {
            try scancode(@as(u16, @intCast(codepoint & 0xFFFF)));
        } else {
            const code = codepoint - 0x10000;
            const lo10 = @as(u16, @intCast(code & 0x3FF));
            const hi10 = @as(u16, @intCast(code >> 10));
            try scancode(0xD800 | hi10);
            try scancode(0xDC00 | lo10);
        }
    }

    pub fn stringDelayed(str: []const u8, delay: u32) !void {
        var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
        var first = true;
        while (iter.nextCodepoint()) |i| {
            if (delay > 0 and !first) Windows.Sleep(delay);
            first = false;
            try char(i);
        }
    }

    pub fn string(str: []const u8) !void {
        try stringDelayed(str, 0);
    }
};

pub const Clipboard = struct {
    pub fn open() !void {
        const result = Windows.OpenClipboard(null);
        if (result == false) return error.FunctionFailed;
    }

    pub fn close() void {
        _ = Windows.CloseClipboard();
    }

    pub fn write(str: []const u8) !void {
        const utf16str = try std.unicode.utf8ToUtf16LeAlloc(std.heap.page_allocator, str);
        defer std.heap.page_allocator.free(utf16str);

        const mem = Windows.GlobalAlloc(2, (utf16str.len + 1) * @sizeOf(u16));
        if (mem == null) return error.AllocFailed;
        errdefer _ = Windows.GlobalFree(mem);

        const memLock = Windows.GlobalLock(mem);
        if (memLock == null) return error.FunctionFailed;
        var memPtr = @as([*]u16, @ptrCast(@alignCast(memLock)))[0 .. utf16str.len + 1];
        @memcpy(memPtr[0..utf16str.len], utf16str);
        memPtr[utf16str.len] = 0;
        if (Windows.GlobalUnlock(mem) == false) {
            if (Windows.GetLastError() != 0) {
                return error.FunctionFailed;
            }
        }
        if (Windows.EmptyClipboard() == false) return error.FunctionFailed;
        if (Windows.SetClipboardData(13, mem) == null) return error.FunctionFailed;
    }

    pub fn set(str: []const u8) !void {
        try open();
        defer close();
        try write(str);
    }
};

pub const Window = struct {
    handle: *anyopaque,

    const Self = @This();

    pub const Rectangle = extern struct {
        left: c_long,
        top: c_long,
        right: c_long,
        bottom: c_long,
    };

    pub fn getFocused() !Self {
        const hwnd = Windows.GetForegroundWindow();
        if (hwnd == null) return error.FunctionFailed;
        return .{ .handle = hwnd.? };
    }

    pub fn getAt(p: Mouse.Point) !Self {
        const hwnd = Windows.WindowFromPoint(p);
        if (hwnd == null) return error.FunctionFailed;
        return .{ .handle = hwnd.? };
    }

    pub fn getNext(self: Self) !Self {
        const hwnd = Windows.GetWindow(self.handle, 1);
        if (hwnd == null) return error.FunctionFailed;
        return .{ .handle = hwnd.? };
    }

    pub fn makeFocused(self: Self) !void {
        if (Windows.SetForegroundWindow(self.handle) == false) return error.FunctionFailed;
    }

    pub fn getRect(self: Self) !Rectangle {
        var rect: Rectangle = undefined;
        if (Windows.GetWindowRect(self.handle, &rect) == false) return error.FunctionFailed;
        return rect;
    }

    pub fn getName(self: Self, alloc: std.mem.Allocator) ![]const u8 {
        const length = Windows.GetWindowTextLengthA(self.handle);
        var name: []u8 = try alloc.alloc(u8, @as(usize, @intCast(length + 1)));
        errdefer alloc.free(name);
        if (Windows.GetWindowTextA(self.handle, name.ptr, length + 1) != length) {
            return error.FunctionFailed;
        }
        return name[0..@as(usize, @intCast(length))];
    }
};

pub fn sleep(millis: u32) void {
    Windows.Sleep(millis);
}

// It is important to note that from this point onward,
// this module does not have any errors, as it is an error
// in an of itself.

const chapterMap = @import("chapter_map.zig");
const argparse = @import("argparse.zig");
const util = @import("util.zig");
const log = @import("log.zig");

/// alloc is an arena, i dont care
pub fn uploadStream(alloc: std.mem.Allocator, cm: chapterMap.MapObject, options: argparse.UploadOptions, ccPath: []const u8, vodDir: std.fs.Dir) !void {
    const w = try Window.getAt(try Mouse.getPosition());
    try w.makeFocused();
    const s = try w.getRect();

    if (options.makePost) {
        log.info("Sending main message and going to comments", .{});
        try Mouse.move(@divTrunc(s.left + (s.right - s.left), 2), s.bottom - 20);
        try Mouse.click(.Left);

        const message = try std.fmt.allocPrint(alloc, "[{s}] {s}", .{ try util.isoDateToHRDate(alloc, cm.date), cm.name });
        try Keyboard.stringDelayed(message, 2);
        try Keyboard.key(.Enter);
        try Keyboard.stringDelayed("в комментариях 👀", 2);
        try Keyboard.keyCombo(&.{ .LCtrl, .Enter });
        sleep(500);
        try Mouse.move(s.left + 110, s.bottom - 90);
        try Mouse.click(.Left);
        sleep(5000);
    }

    if (options.uploadCC) {
        log.info("Sending CC", .{});
        try Mouse.move(s.left + 100, s.bottom - 10);
        try Mouse.click(.Left);
        sleep(500);
        const filepicker = try Window.getFocused();
        const fs = try filepicker.getRect();
        try Mouse.move(fs.left + @divTrunc(fs.right - fs.left, 2), fs.bottom - 70);
        try Mouse.click(.Left);
        sleep(500);
        try Keyboard.stringDelayed(try std.fs.realpathAlloc(alloc, ccPath), 2);
        try Mouse.move(fs.right - 150, fs.bottom - 40);
        try Mouse.click(.Left);
        sleep(2000);
        try Mouse.move(s.left + @divTrunc(s.right - s.left, 2), s.top + @divTrunc(s.bottom - s.top, 2));
        try Mouse.click(.Left);
        try Keyboard.string("[запись чата]");
        try Keyboard.keyCombo(&.{ .LCtrl, .Enter });
        sleep(1000);
    }

    for (options.uploadFromChunk - 1..cm.chunks.len) |i| {
        log.info("Sending chunk #{}", .{i + 1});
        try Mouse.move(s.left + 100, s.bottom - 10);
        try Mouse.click(.Left);
        sleep(500);
        const filepicker = try Window.getFocused();
        const fs = try filepicker.getRect();
        try Mouse.move(fs.left + @divTrunc(fs.right - fs.left, 2), fs.bottom - 70);
        try Mouse.click(.Left);
        sleep(500);
        const name = try std.fmt.allocPrint(alloc, "{}.mp4", .{i + 1});
        try Keyboard.string(try vodDir.realpathAlloc(alloc, name));
        try Mouse.move(fs.right - 150, fs.bottom - 40);
        try Mouse.click(.Left);
        sleep(2000);
        try Mouse.move(s.left + @divTrunc(s.right - s.left, 2), s.top + @divTrunc(s.bottom - s.top, 2));
        try Mouse.click(.Left);
        const chunk = cm.chunks[i];
        const msg = try std.fmt.allocPrint(alloc, "[часть №{}]", .{i + 1});
        try Keyboard.string(msg);
        try Keyboard.key(.Enter);
        sleep(50);
        for (0..chunk.len) |j| {
            const chapter = chunk[j];
            const c = try std.fmt.allocPrint(alloc, "{s} - {s}", .{ util.secondsIntoLength(alloc, chapter.start) catch unreachable, chapter.name });
            try Keyboard.string(c);
            try Keyboard.key(.Enter);
            sleep(50);
        }
        try Keyboard.keyCombo(&.{ .LCtrl, .Enter });
        sleep(1000);
    }
}
