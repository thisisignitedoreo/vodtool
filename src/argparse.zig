const std = @import("std");
const builtin = @import("builtin");

const log = @import("log.zig");

pub const UploadOptions = struct {
    makePost: bool,
    uploadCC: bool,
    uploadFromChunk: u64,
};

pub const Args = union(enum) {
    download: struct {
        streamPlatform: enum { twitch },
        streamUid: []const u8,
    },
    categorize: struct {
        streamUid: []const u8,
    },
    printChapterMap: struct {
        streamUid: []const u8,
    },
    upload: struct {
        streamUid: []const u8,
        uploadOptions: UploadOptions,
    },
};

fn usage(program: []const u8) void {
    log.usage("{s} <subcommand> [args]", .{program});
    log.usage("", .{});
    log.usage("Subcommands:", .{});
    log.usage("  help", .{});
    log.usage("    Print this message and exit", .{});
    log.usage("  download <-u <twitch stream ID>|link>", .{});
    log.usage("    Download a stream, split it and generate a chapter map", .{});
    log.usage("    Twitch streams will be saved under their ID (e.g. 2473295087)", .{});
    log.usage("  categorize <stream UID>", .{});
    log.usage("    Split a stream from a file and generate a chapter map", .{});
    log.usage("  print-chapter-map <stream UID>", .{});
    log.usage("    Print chapter map in the human-readable-and-copypastable format (HRAC)", .{});
    log.usage("  upload <stream UID> [--post] [--no-chat] [--from-chunk N]", .{});
    log.usage("    Use Win32 Api to manipulate mouse and keyboard to send the VOD to Telegram", .{});
}

fn parseSingleUid(program: []const u8, iter: *std.process.ArgIterator) ![]const u8 {
    var uid: ?[]const u8 = null;
    while (iter.next()) |a| {
        if (uid != null) {
            usage(program);
            log.fatal("Multiple UID `print-chapter-map` isn't supported", .{});
            return error.TooManyArguments;
        }
        uid = a;
    }
    if (uid == null) {
        usage(program);
        log.fatal("Expected a UID", .{});
        return error.ExpectedArgument;
    }
    return uid.?;
}

pub fn parse(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.ArgIterator.initWithAllocator(alloc);
    const program = iter.next().?;
    const subcommand = iter.next() orelse {
        usage(program);
        log.fatal("Expected a subcommand", .{});
        return error.NoSubcommand;
    };
    if (std.mem.eql(u8, subcommand, "help")) {
        usage(program);
        return error.HelpPrinted;
    } else if (std.mem.eql(u8, subcommand, "download")) {
        var uid: ?[]const u8 = null;
        while (iter.next()) |a| {
            if (uid != null) {
                usage(program);
                log.fatal("Multiple ID/link downloads aren't supported", .{});
                return error.TooManyArguments;
            }
            if (std.mem.eql(u8, a, "-u")) {
                uid = iter.next() orelse {
                    usage(program);
                    log.fatal("Expected a twitch ID", .{});
                    return error.ExpectedArgument;
                };
            } else {
                var sIter: std.mem.SplitIterator(u8, .sequence) = undefined;
                if (std.mem.startsWith(u8, a, "https://twitch.tv/videos/")) {
                    sIter = std.mem.splitSequence(u8, a["https://twitch.tv/videos/".len..], "?");
                } else if (std.mem.startsWith(u8, a, "https://www.twitch.tv/videos/")) {
                    sIter = std.mem.splitSequence(u8, a["https://www.twitch.tv/videos/".len..], "?");
                } else {
                    usage(program);
                    log.fatal("Expected a link", .{});
                    return error.InvalidArgument;
                }
                uid = sIter.first();
            }
        }
        if (uid == null) {
            usage(program);
            log.fatal("Expected a UID/link", .{});
            return error.ExpectedArgument;
        }
        return Args{
            .download = .{
                .streamPlatform = .twitch,
                .streamUid = uid.?,
            },
        };
    } else if (std.mem.eql(u8, subcommand, "categorize")) {
        return Args{
            .categorize = .{
                .streamUid = try parseSingleUid(program, &iter),
            },
        };
    } else if (std.mem.eql(u8, subcommand, "print-chapter-map")) {
        return Args{
            .printChapterMap = .{
                .streamUid = try parseSingleUid(program, &iter),
            },
        };
    } else if (std.mem.eql(u8, subcommand, "upload")) {
        if (builtin.target.os.tag != .windows) {
            log.fatal("This feature works only under Windows", .{});
            return error.WindowsOnly;
        }
        var uid: ?[]const u8 = null;
        var options = UploadOptions{
            .makePost = false,
            .uploadCC = true,
            .uploadFromChunk = 1,
        };
        while (iter.next()) |a| {
            if (std.mem.eql(u8, a, "--post")) {
                options.makePost = true;
            } else if (std.mem.eql(u8, a, "--no-chat")) {
                options.uploadCC = false;
            } else if (std.mem.eql(u8, a, "--from-chunk")) {
                const f = iter.next() orelse {
                    usage(program);
                    log.fatal("Expected a number", .{});
                    return error.ExpectedArgument;
                };
                options.uploadFromChunk = std.fmt.parseUnsigned(u64, f, 0) catch |e| {
                    usage(program);
                    log.fatal("Invalid number", .{});
                    return e;
                };
            } else {
                if (uid != null) {
                    usage(program);
                    log.fatal("Multiple UID `upload` isn't supported", .{});
                    return error.TooManyArguments;
                }
                uid = a;
            }
        }
        if (uid == null) {
            usage(program);
            log.fatal("Expected a UID", .{});
            return error.ExpectedArgument;
        }
        return Args{
            .upload = .{
                .streamUid = uid.?,
                .uploadOptions = options,
            },
        };
    }
    usage(program);
    log.fatal("Invalid subcommand", .{});
    return error.InvalidSubcommand;
}
