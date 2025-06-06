const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");
const argparse = @import("argparse.zig");
const util = @import("util.zig");
const chapterMap = @import("chapter_map.zig");
const automation = if (builtin.target.os.tag == .windows) @import("automation.zig") else null;

pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    log.init();

    const alloc = arena.allocator();

    var cwd = std.fs.cwd();

    const args = argparse.parse(alloc) catch return 1;
    switch (args) {
        .download => {
            if (args.download.streamPlatform == .twitch) {
                const uid = args.download.streamUid;

                const vodPath = std.fmt.allocPrint(alloc, "vods/{s}.mp4", .{uid}) catch return 1;
                const chatPath = std.fmt.allocPrint(alloc, "vods/{s}.json", .{uid}) catch return 1;
                const dirPath = std.fmt.allocPrint(alloc, "vods/{s}", .{uid}) catch return 1;
                const cmPath = std.fmt.allocPrint(alloc, "vods/{s}.map.json", .{uid}) catch return 1;

                if (cwd.access(vodPath, .{})) {
                    log.info("VOD twitch:{s} already downloaded, skipping", .{uid});
                } else |_| {
                    log.info("Downloading VOD twitch:{s}", .{uid});
                    util.Twitch.downloadStream(alloc, uid, vodPath) catch {
                        log.fatal("Couldn't download the VOD from Twitch", .{});
                        return 1;
                    };
                }

                if (cwd.access(chatPath, .{})) {
                    log.info("Chat Capture for VOD twitch:{s} already downloaded, skipping", .{uid});
                } else |_| {
                    log.info("Downloading Chat Capture for VOD twitch:{s}", .{uid});
                    util.Twitch.downloadChat(alloc, uid, chatPath) catch {
                        log.fatal("Couldn't download the Chat Capture", .{});
                        return 1;
                    };
                }

                var vodDir = cwd.openDir(dirPath, .{}) catch |e| switch (e) {
                    error.NotDir => brk: {
                        cwd.deleteFile(dirPath) catch {
                            log.fatal("vods/{s} is a file, and it couldn't be deleted", .{uid});
                            return 1;
                        };
                        cwd.makePath(dirPath) catch {
                            log.fatal("Couldn't create vods/{s}", .{uid});
                            return 1;
                        };
                        break :brk cwd.openDir(dirPath, .{}) catch unreachable;
                    },
                    error.FileNotFound => brk: {
                        cwd.makePath(dirPath) catch {
                            log.fatal("Couldn't create vods/{s}", .{uid});
                            return 1;
                        };
                        break :brk cwd.openDir(dirPath, .{}) catch unreachable;
                    },
                    else => {
                        log.fatal("Couldn't open vods/{s}", .{uid});
                        return 1;
                    },
                };
                defer vodDir.close();

                const chunkSizes = util.splitStream(alloc, vodDir, vodPath) catch {
                    log.fatal("Couldn't split VOD twitch:{s}", .{uid});
                    return 1;
                };

                const info = util.Twitch.loadInfoFromCC(alloc, chatPath) catch |e| {
                    if (e == error.MalformedCC) {
                        log.fatal("Malformed chat capture format", .{});
                    } else {
                        log.fatal("Couldn't read chat capture", .{});
                    }
                    return 1;
                };

                chapterMap.writeMap(alloc, cmPath, info, chunkSizes) catch {
                    log.fatal("Couldn't make a chapter map", .{});
                    return 1;
                };

                log.info("Successfully downloaded and split VOD twitch:{s}", .{uid});
                log.info("Saved in cache under the UID `{s}`", .{uid});
            }
        },
        .categorize => {
            const uid = args.categorize.streamUid;

            const vodPath = std.fmt.allocPrint(alloc, "vods/{s}.mp4", .{uid}) catch return 1;
            const catPath = std.fmt.allocPrint(alloc, "vods/{s}.cat.txt", .{uid}) catch return 1;
            const dirPath = std.fmt.allocPrint(alloc, "vods/{s}", .{uid}) catch return 1;
            const cmPath = std.fmt.allocPrint(alloc, "vods/{s}.map.json", .{uid}) catch return 1;

            var vodDir = cwd.openDir(dirPath, .{}) catch |e| switch (e) {
                error.NotDir => brk: {
                    cwd.deleteFile(dirPath) catch {
                        log.fatal("vods/{s} is a file, and it couldn't be deleted", .{uid});
                        return 1;
                    };
                    cwd.makePath(dirPath) catch {
                        log.fatal("Couldn't create vods/{s}", .{uid});
                        return 1;
                    };
                    break :brk cwd.openDir(dirPath, .{}) catch unreachable;
                },
                error.FileNotFound => brk: {
                    cwd.makePath(dirPath) catch {
                        log.fatal("Couldn't create vods/{s}", .{uid});
                        return 1;
                    };
                    break :brk cwd.openDir(dirPath, .{}) catch unreachable;
                },
                else => {
                    log.fatal("Couldn't open vods/{s}", .{uid});
                    return 1;
                },
            };
            defer vodDir.close();

            const chunkSizes = util.splitStream(alloc, vodDir, vodPath) catch {
                log.fatal("Couldn't split VOD {s}", .{uid});
                return 1;
            };

            const info = util.loadInfoFromCat(alloc, catPath) catch |e| {
                if (e == error.MalformedCat) {
                    log.fatal("Malformed stream info format", .{});
                } else {
                    log.fatal("Couldn't read stream info", .{});
                }
                return 1;
            };

            chapterMap.writeMap(alloc, cmPath, info, chunkSizes) catch {
                log.fatal("Couldn't make a chapter map", .{});
                return 1;
            };

            log.info("Successfully split VOD `{s}`", .{uid});
        },
        .printChapterMap => {
            const uid = args.printChapterMap.streamUid;
            const cmPath = std.fmt.allocPrint(alloc, "vods/{s}.map.json", .{uid}) catch return 1;
            const cm = chapterMap.parseMap(alloc, cmPath) catch |e| {
                if (e == error.FileNotFound) {
                    log.fatal("No chapter map for this VOD found", .{});
                } else {
                    log.fatal("Couldn't parse chapter map", .{});
                }
                return 1;
            };

            for (0..cm.value.chunks.len) |i| {
                const chunk = cm.value.chunks[i];
                log.print("\n[часть №{}]", .{i + 1});
                for (0..chunk.len) |j| {
                    const chapter = chunk[j];
                    log.print("\n{s} - {s}", .{ util.secondsIntoLength(alloc, chapter.start) catch unreachable, chapter.name });
                }
                log.print("\n", .{});
            }
            log.print("\n[{s}] {s}\nв комментариях 👀\n", .{ util.isoDateToHRDate(alloc, cm.value.date) catch "00.00.0000", cm.value.name });
        },
        .upload => {
            const uid = args.upload.streamUid;
            const ccPath = std.fmt.allocPrint(alloc, "vods/{s}.json", .{uid}) catch return 1;
            const dirPath = std.fmt.allocPrint(alloc, "vods/{s}/", .{uid}) catch return 1;
            const cmPath = std.fmt.allocPrint(alloc, "vods/{s}.map.json", .{uid}) catch return 1;
            const cm = chapterMap.parseMap(alloc, cmPath) catch |e| {
                if (e == error.FileNotFound) {
                    log.fatal("No chapter map for this VOD found", .{});
                } else {
                    log.fatal("Couldn't parse chapter map", .{});
                }
                return 1;
            };
            var vodDir = cwd.openDir(dirPath, .{}) catch {
                log.fatal("Couldn't open vods/{s}", .{uid});
                return 1;
            };
            defer vodDir.close();

            // By here, we can assume the OS is Windows
            // A hint for the optimizer so that it does not compile code below this point
            // under a non-windows target, which causes a compile error. (See line 8)
            if (builtin.target.os.tag != .windows) return 1;

            automation.uploadStream(alloc, cm.value, args.upload.uploadOptions, ccPath, vodDir) catch {
                log.fatal("Failed to send input to the OS", .{});
                return 1;
            };
        },
    }

    {
        cwd.deleteFile("COPYRIGHT.txt") catch {};
        cwd.deleteFile("THIRD-PARTY-LICENSES.txt") catch {};

        // the real question is this: was all this legal?
        // absolutely fucking not!
    }

    return 0;
}
