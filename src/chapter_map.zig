const std = @import("std");
const util = @import("util.zig");
const log = @import("log.zig");

const MapChapter = struct {
    name: []const u8,
    start: f32,
};

pub const MapObject = struct {
    name: []const u8,
    date: []const u8,
    chunks: [][]MapChapter,
};

pub fn makeMap(
    alloc: std.mem.Allocator,
    info: util.StreamInfo,
    chunkSizes: []f32,
) !MapObject {
    log.info("Generating chapter map", .{});

    var chunks = std.ArrayList([]MapChapter).init(alloc);
    errdefer chunks.deinit();

    var chapter: u32 = 0;
    var chapterStart: f32 = 0;
    var chapterOffset: f32 = 0;

    var chunkStart: f32 = 0;

    for (0..chunkSizes.len) |i| {
        const chunkSize = chunkSizes[i];

        var chunk = std.ArrayList(MapChapter).init(alloc);
        errdefer chunk.deinit();

        const chunkEnd = chunkStart + chunkSize;

        while (chapterStart + chapterOffset < chunkEnd) {
            if (chapter >= info.chapters.len) break;
            const chapterObj = info.chapters[chapter];
            chapterStart = @as(f32, @floatFromInt(chapterObj.start));

            try chunk.append(MapChapter{ .name = chapterObj.name, .start = chapterStart + chapterOffset - chunkStart });

            if (chapterStart + @as(f32, @floatFromInt(chapterObj.length)) > chunkEnd) {
                chapterOffset += (chunkStart + chunkSize) - (chapterStart + chapterOffset);
            } else {
                chapter += 1;
                chapterOffset = 0;
            }
        }

        chunkStart += chunkSize;
        try chunks.append(try chunk.toOwnedSlice());
    }

    return MapObject{
        .name = info.name,
        .date = info.date,
        .chunks = try chunks.toOwnedSlice(),
    };
}

pub fn parseMap(alloc: std.mem.Allocator, path: []const u8) !std.json.Parsed(MapObject) {
    const fileContent = try std.fs.cwd().readFileAlloc(alloc, path, 20 * 1024);
    return std.json.parseFromSlice(MapObject, alloc, fileContent, .{});
}

pub fn writeMap(
    alloc: std.mem.Allocator,
    path: []const u8,
    info: util.StreamInfo,
    chunkSizes: []f32,
) !void {
    const map = try makeMap(alloc, info, chunkSizes);

    var cwd = std.fs.cwd();
    try cwd.writeFile(.{ .sub_path = path, .data = try std.json.stringifyAlloc(alloc, map, .{}) });
}
