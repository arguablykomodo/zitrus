const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

var line_buf: [16 + 10 + 3]u8 = undefined; // row name + places for a u32 + unit

fn parseLine(reader: *const std.fs.File.Reader) !u32 {
    const line = try reader.readUntilDelimiter(&line_buf, '\n');

    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip row name

    return try std.fmt.parseUnsigned(u32, tokens.next() orelse unreachable, 10);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.nextPosix()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (std.time.sleep(interval * 1000000)) {
        const file = try std.fs.openFileAbsolute("/proc/meminfo", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        const total = try parseLine(&reader); // MemTotal
        try reader.skipUntilDelimiterOrEof('\n'); // MemFree
        const available = try parseLine(&reader); // MemAvailable

        const percentage = 1 - @intToFloat(f32, available) / @intToFloat(f32, total);
        try writePercentage(percentage, stdout);
        try stdout.writeByte(' ');
        try writeBar(percentage, colors, stdout);
        try stdout.writeByte('\n');
    }
}
