const std = @import("std");

const log = @import("log.zig");

pub fn run(alloc: std.mem.Allocator, argv: []const []const u8) !void {
    var process = std.process.Child.init(argv, alloc);
    process.stdin_behavior = .Ignore;

    const term = try process.spawnAndWait();
    if (term.Exited != 0) return error.ProgramReportedFailure;
}

pub fn runCaptured(alloc: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv,
    });
}

pub const Chapter = struct {
    name: []const u8,
    start: u64,
    length: u64,
};

pub const StreamInfo = struct {
    name: []const u8,
    date: []const u8,
    chapters: []Chapter,
};

pub const Twitch = struct {
    pub fn downloadStream(alloc: std.mem.Allocator, uid: []const u8, outputPath: []const u8) !void {
        const link = try std.fmt.allocPrint(alloc, "https://twitch.tv/videos/{s}", .{uid});
        defer alloc.free(link);

        try run(alloc, &.{ "yt-dlp", link, "-o", outputPath, "-N", "12" });
    }

    pub fn downloadChat(alloc: std.mem.Allocator, uid: []const u8, outputPath: []const u8) !void {
        try run(alloc, &.{ "ttvdl", "chatdownload", "-u", uid, "-o", outputPath });
    }

    pub fn loadChaptersFromCC(alloc: std.mem.Allocator, value: std.json.Parsed(std.json.Value)) ![]Chapter {
        const value_video = value.value.object.get("video") orelse return error.MalformedCC;
        const value_chapters = value_video.object.get("chapters") orelse return error.MalformedCC;
        return switch (value_chapters) {
            .array => ret: {
                var chapters = std.ArrayList(Chapter).init(alloc);
                errdefer chapters.deinit();
                for (0..value_chapters.array.items.len) |i| {
                    var chapter = value_chapters.array.items[i];
                    const description = chapter.object.get("description") orelse return error.MalformedCC;
                    const start = chapter.object.get("startMilliseconds") orelse return error.MalformedCC;
                    const length = chapter.object.get("lengthMilliseconds") orelse return error.MalformedCC;
                    try chapters.append(Chapter{
                        .name = description.string,
                        .start = switch (start) {
                            .integer => @as(u64, @intCast(start.integer)) / 1000,
                            else => return error.MalformedCC,
                        },
                        .length = switch (length) {
                            .integer => @as(u64, @intCast(length.integer)) / 1000,
                            else => return error.MalformedCC,
                        },
                    });
                }
                break :ret try chapters.toOwnedSlice();
            },
            else => error.MalformedCC,
        };
    }

    pub fn loadInfoFromCC(alloc: std.mem.Allocator, cc: []const u8) !StreamInfo {
        const path = try std.fs.realpathAlloc(alloc, cc);
        defer alloc.free(path);

        var file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(alloc, 50 * 1024 * 1024);
        defer alloc.free(content);

        var value = try std.json.parseFromSlice(std.json.Value, alloc, content, .{});
        defer value.deinit();

        const value_video = value.value.object.get("video") orelse return error.MalformedCC;

        return StreamInfo{
            .name = ret: {
                const title = value_video.object.get("title") orelse return error.MalformedCC;
                break :ret switch (title) {
                    .string => title.string,
                    else => return error.MalformedCC,
                };
            },
            .date = ret: {
                const date = value_video.object.get("created_at") orelse return error.MalformedCC;
                break :ret switch (date) {
                    .string => date.string,
                    else => return error.MalformedCC,
                };
            },
            .chapters = try loadChaptersFromCC(alloc, value),
        };
    }
};

fn SliceReader(comptime T: type) type {
    return struct {
        slice: []T,
        cursor: usize,

        const Self = @This();

        pub fn init(slice: []T) Self {
            return Self{ .slice = slice, .cursor = 0 };
        }

        pub fn notEmpty(self: Self) bool {
            return self.cursor < self.slice.len;
        }

        pub fn read(self: *Self) ?T {
            if (self.cursor >= self.slice.len) {
                return null;
            } else {
                self.cursor += 1;
                return self.slice[self.cursor - 1];
            }
        }

        pub fn readUntil(self: *Self, delim: T) ?[]T {
            if (self.cursor >= self.slice.len) return null;
            var size: usize = 0;
            while (self.cursor < self.slice.len + size and self.slice[size] != delim) {
                size += 1;
            }
            size += 1;
            self.cursor += size;
            return self.slice[self.cursor - size .. size];
        }
    };
}

pub fn isoDateToHRDate(alloc: std.mem.Allocator, str: []const u8) ![]const u8 {
    var a = std.ArrayList(u8).init(alloc);
    errdefer a.deinit();

    // TODO: implement like, actual parsing?
    if (str.len < 10) return error.NotImplemented;
    try a.append(str[8]);
    try a.append(str[9]);
    try a.append('.');
    try a.append(str[5]);
    try a.append(str[6]);
    try a.append('.');
    try a.append(str[0]);
    try a.append(str[1]);
    try a.append(str[2]);
    try a.append(str[3]);

    return a.toOwnedSlice();
}

pub fn parseLength(str: []const u8) !u64 {
    if (str.len == 8) {
        if (std.ascii.isDigit(str[0]) and std.ascii.isDigit(str[1]) and std.ascii.isDigit(str[3]) and std.ascii.isDigit(str[4]) and std.ascii.isDigit(str[6]) and std.ascii.isDigit(str[7]) and str[2] == ':' and str[5] == ':') {
            const hour = (str[0] - '0') * 10 + str[1] - '0';
            const min = (str[3] - '0') * 10 + str[4] - '0';
            const sec = (str[6] - '0') * 10 + str[7] - '0';
            if (min >= 60) return error.MalformedCat;
            if (sec >= 60) return error.MalformedCat;
            return sec + min * 60 + hour * 60 * 60;
        }
    }
    return try std.fmt.parseUnsigned(u64, str, 0);
}

pub fn loadInfoFromCat(alloc: std.mem.Allocator, cat: []const u8) !StreamInfo {
    var info: StreamInfo = undefined;

    const path = try std.fs.realpathAlloc(alloc, cat);
    defer alloc.free(path);

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(alloc, 20 * 1024);
    errdefer alloc.free(content);

    var stream = SliceReader(u8).init(content);

    info.date = stream.readUntil(' ') orelse return error.MalformedCat;
    info.name = stream.readUntil('\n') orelse return error.MalformedCat;
    if (std.mem.endsWith(u8, info.name, "\r")) info.name.len -= 1;

    var chapters = std.ArrayList(Chapter).init(alloc);
    errdefer chapters.deinit();

    var startCursor: u64 = 0;
    while (stream.readUntil('\n')) |line| {
        var lineStream = SliceReader(u8).init(line);

        const length = lineStream.readUntil(' ') orelse return error.MalformedCat;
        var name = lineStream.readUntil('\n') orelse return error.MalformedCat;
        if (std.mem.endsWith(u8, name, "\r")) name.len -= 1;

        try chapters.append(Chapter{
            .start = startCursor,
            .length = try parseLength(length),
            .name = name,
        });
        startCursor += try parseLength(length);
    }

    info.chapters = try chapters.toOwnedSlice();

    return info;
}

pub fn getLength(alloc: std.mem.Allocator, path: []const u8) !f32 {
    const fullpath = try std.fs.realpathAlloc(alloc, path);
    defer alloc.free(fullpath);

    const result = try runCaptured(alloc, &.{ "ffprobe", "-i", fullpath, "-show_format", "-v", "quiet" });
    if (result.term.Exited != 0) return error.ProgramReportedFailure;
    var length: f32 = 1.0;

    var iter = std.mem.splitSequence(u8, result.stdout, "\n");
    _ = iter.first(); // == "[FORMAT]"
    while (iter.next()) |w| {
        if (std.mem.startsWith(u8, w, "duration=")) {
            var lstr = w["duration=".len..];
            if (std.mem.endsWith(u8, lstr, "\r")) lstr = lstr[0 .. lstr.len - 1];
            if (!std.mem.startsWith(u8, lstr, "N/A")) {
                length = try std.fmt.parseFloat(f32, lstr);
            }
            break;
        }
    }
    return length;
}

pub fn secondsIntoLength(alloc: std.mem.Allocator, l: f32) ![]const u8 {
    const m: u32 = @as(u32, @intFromFloat(l)) / 60;
    const h: u32 = m / 60;
    const s: u32 = @as(u32, @intFromFloat(l));
    return try std.fmt.allocPrint(alloc, "{:0>2}:{:0>2}:{:0>2}", .{ h, m % 60, s % 60 });
}

pub fn bytesIntoKibi(alloc: std.mem.Allocator, s: u64) ![]const u8 {
    // if b < 1024: return f"{b}B"
    // elif b < 1024**2: return f"{b/1024:.1f}KiB"
    // elif b < 1024**3: return f"{b/(1024**2):.1f}MiB"
    // elif b < 1024**4: return f"{b/(1024**3):.1f}GiB"
    // return f"{b/(1024**4):.1f}TiB"
    if (s < 1024) {
        return try std.fmt.allocPrint(alloc, "{:0>2}B", .{s});
    } else if (s < try std.math.powi(u64, 1024, 2)) {
        return try std.fmt.allocPrint(alloc, "{d:0>2.1}KiB", .{
            @as(f32, @floatFromInt(s)) / @as(f32, 1024.0),
        });
    } else if (s < try std.math.powi(u64, 1024, 3)) {
        return try std.fmt.allocPrint(alloc, "{d:0>2.1}MiB", .{
            @as(f32, @floatFromInt(s)) / std.math.pow(f32, 1024, 2),
        });
    } else if (s < try std.math.powi(u64, 1024, 4)) {
        return try std.fmt.allocPrint(alloc, "{d:0>2.1}GiB", .{
            @as(f32, @floatFromInt(s)) / std.math.pow(f32, 1024, 3),
        });
    } else {
        return try std.fmt.allocPrint(alloc, "{d:0>2.1}TiB", .{
            @as(f32, @floatFromInt(s)) / std.math.pow(f32, 1024, 4),
        });
    }
}

pub fn splitStream(a: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) ![]f32 {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();

    const alloc = arena.allocator();

    const fullpath = try std.fs.realpathAlloc(alloc, path);

    const chunkSize: f32 = 2_000_000_000;
    const fullLength = try getLength(alloc, fullpath);
    var cursor: f32 = 0.0;
    var chunks: u32 = 0;
    var chunkSizes = std.ArrayList(f32).init(alloc);

    log.info("Splitting file `{s}` ({s}) into chunks of size {s}", .{ std.fs.path.basename(path), try secondsIntoLength(alloc, fullLength), try bytesIntoKibi(alloc, chunkSize) });

    while (cursor < fullLength) {
        chunks += 1;

        const chunkFilename = try std.fmt.allocPrint(alloc, "{}.mp4", .{chunks});
        try dir.writeFile(.{ .sub_path = chunkFilename, .data = "" });
        // ^ this is a hack, but it works
        const chunkPath = try dir.realpathAlloc(alloc, chunkFilename);
        defer alloc.free(chunkPath);

        _ = try runCaptured(alloc, &.{
            "ffmpeg",
            "-ss",
            try std.fmt.allocPrint(alloc, "{d}", .{cursor}),
            "-i",
            fullpath,
            "-fs",
            try std.fmt.allocPrint(alloc, "{d}", .{chunkSize}),
            "-c",
            "copy",
            chunkPath,
            "-y",
        });

        const chunkLength = try getLength(alloc, chunkPath);
        try chunkSizes.append(chunkLength);

        const file = try std.fs.openFileAbsolute(chunkPath, .{});
        defer file.close();
        log.info("Chunk #{:0>2}: {s}..{s} ({s})", .{ chunks, try secondsIntoLength(alloc, cursor), try secondsIntoLength(alloc, cursor + chunkLength), try bytesIntoKibi(alloc, (try file.metadata()).size()) });

        cursor += chunkLength;
    }

    return try chunkSizes.toOwnedSlice();
}
