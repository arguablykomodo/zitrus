const std = @import("std");

var column: u4 = undefined;
var prev_bytes: u64 = 0;
var line_buf: [6 + 1 + (1 + 19) * 16]u8 = undefined; // name + colon + (space + u64) * columns
var stdout_buffer: [1024]u8 = undefined;

fn parseLine(reader: *std.Io.Reader) !?u64 {
    const line = if (reader.takeDelimiterExclusive('\n')) |l| l else |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };

    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    _ = tokens.next(); // skip interface name

    var i: u4 = 0;
    while (tokens.next()) |token| : (i += 1) {
        if (i == column) return try std.fmt.parseUnsigned(u64, token, 10);
    }

    unreachable;
}

pub fn main() !void {
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = std.process.args();
    const launch_arg = args.next().?;

    if (args.next()) |arg| {
        column = if (std.mem.eql(u8, arg, "down")) 0 else if (std.mem.eql(u8, arg, "up")) 8 else {
            std.log.err("argument must be \"down\" or \"up\", instead found \"{s}\"", .{arg});
            std.process.exit(1);
        };
    } else {
        try stdout.print("usage: {s} down|up [interval]\n", .{launch_arg});
        return;
    }

    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;

    while (true) : (std.Thread.sleep(interval * std.time.ns_per_ms)) {
        const file = try std.fs.openFileAbsolute("/proc/net/dev", .{});
        defer file.close();
        var reader = file.reader(&line_buf);

        _ = try reader.interface.discardDelimiterInclusive('\n'); // header 1
        _ = try reader.interface.discardDelimiterInclusive('\n'); // header 2
        _ = try reader.interface.discardDelimiterInclusive('\n'); // loopback

        var new_bytes: u64 = 0;
        while (try parseLine(&reader.interface)) |bytes| {
            new_bytes += bytes;
        }

        const speed = (new_bytes - prev_bytes) * std.time.ms_per_s / interval;

        try stdout.printByteSize(speed, .decimal, .{ .precision = 0 });
        try stdout.writeByte('\n');
        try stdout.flush();

        prev_bytes = new_bytes;
    }
}
