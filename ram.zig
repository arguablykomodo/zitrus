const std = @import("std");
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

// row name + places for a u32 + unit
const MAX_LINE_LENGTH = 16 + 10 + 3;

const INTERVAL = 1000000000;

var line_buf: [MAX_LINE_LENGTH]u8 = undefined;

fn parseLine(reader: *const std.fs.File.Reader) !u32 {
    const line = try reader.readUntilDelimiter(&line_buf, '\n');

    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip row name

    return try std.fmt.parseUnsigned(u32, tokens.next() orelse unreachable, 10);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    while (true) : (std.time.sleep(INTERVAL)) {
        const file = try std.fs.openFileAbsolute("/proc/meminfo", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        const total = try parseLine(&reader); // MemTotal
        try reader.skipUntilDelimiterOrEof('\n'); // MemFree
        const available = try parseLine(&reader); // MemAvailable

        const percentage = 1 - @intToFloat(f32, available) / @intToFloat(f32, total);
        try writePercentage(percentage, stdout);
        try stdout.writeByte(' ');
        try writeBar(percentage, stdout);
        try stdout.writeByte('\n');
    }
}
