const std = @import("std");

var column: u4 = undefined;
var prev_bytes: u64 = 0;
var line_buf: [6 + 1 + (1 + 19) * 16]u8 = undefined; // name + colon + (space + u64) * columns

fn parseLine(reader: *const std.fs.File.Reader) !?u64 {
    const line = if (reader.readUntilDelimiter(&line_buf, '\n')) |l| l else |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };

    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip interface name

    var i: u4 = 0;
    while (tokens.next()) |token| : (i += 1) {
        if (i == column) return try std.fmt.parseUnsigned(u64, token, 10);
    }

    unreachable;
}

pub fn main() !void {
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = writer.writer();

    var args = std.process.args();
    const launch_arg = args.nextPosix().?;

    if (args.nextPosix()) |arg| {
        column = if (std.mem.eql(u8, arg, "down")) 0 else if (std.mem.eql(u8, arg, "up")) 8 else {
            std.log.err("argument must be \"down\" or \"up\", instead found \"{s}\"", .{arg});
            std.os.exit(1);
        };
    } else {
        try std.fmt.format(stdout, "usage: {s} down|up [interval]\n", .{launch_arg});
        return;
    }

    const interval = if (args.nextPosix()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;

    while (true) : (std.time.sleep(interval * std.time.ns_per_ms)) {
        const file = try std.fs.openFileAbsolute("/proc/net/dev", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        try reader.skipUntilDelimiterOrEof('\n'); // header 1
        try reader.skipUntilDelimiterOrEof('\n'); // header 2
        try reader.skipUntilDelimiterOrEof('\n'); // loopback

        var new_bytes: u64 = 0;
        while (try parseLine(&reader)) |bytes| {
            new_bytes += bytes;
        }

        const speed = (new_bytes - prev_bytes) * std.time.ms_per_s / interval;

        try std.fmt.format(stdout, "{:.0}\n", .{std.fmt.fmtIntSizeDec(speed)});
        try writer.flush();

        prev_bytes = new_bytes;
    }
}
