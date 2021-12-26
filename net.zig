const std = @import("std");

const Bytes = struct { up: u64, down: u64 };

var prev_bytes: Bytes = .{ .up = 0, .down = 0 };
var line_buf: [6 + 1 + (1 + 19) * 16]u8 = undefined; // name + colon + (space + u64) * columns

fn parseLine(reader: *const std.fs.File.Reader) !?Bytes {
    const line = if (reader.readUntilDelimiter(&line_buf, '\n')) |l| l else |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };

    var bytes = Bytes{ .up = undefined, .down = undefined };
    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip name

    bytes.down = try std.fmt.parseUnsigned(u64, tokens.next() orelse unreachable, 10);
    _ = tokens.next(); // packets
    _ = tokens.next(); // errs
    _ = tokens.next(); // drop
    _ = tokens.next(); // fifo
    _ = tokens.next(); // frame
    _ = tokens.next(); // compressed
    _ = tokens.next(); // multicast
    bytes.up = try std.fmt.parseUnsigned(u64, tokens.next() orelse unreachable, 10);

    return bytes;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.nextPosix()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;

    while (true) : (std.time.sleep(interval * 1000000)) {
        const file = try std.fs.openFileAbsolute("/proc/net/dev", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        try reader.skipUntilDelimiterOrEof('\n'); // header 1
        try reader.skipUntilDelimiterOrEof('\n'); // header 2
        try reader.skipUntilDelimiterOrEof('\n'); // loopback

        var new_bytes = Bytes{ .up = 0, .down = 0 };
        while (try parseLine(&reader)) |bytes| {
            new_bytes.up += bytes.up;
            new_bytes.down += bytes.down;
        }

        const up_speed = (new_bytes.up - prev_bytes.up) * 1000 / interval;
        const down_speed = (new_bytes.down - prev_bytes.down) * 1000 / interval;

        try std.fmt.format(stdout, "↓{:.0} ↑{:.0}\n", .{
            std.fmt.fmtIntSizeDec(down_speed),
            std.fmt.fmtIntSizeDec(up_speed)
        });

        prev_bytes = new_bytes;
    }
}
