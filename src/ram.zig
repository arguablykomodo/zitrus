const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

var line_buf: [16 + 10 + 3]u8 = undefined; // row name + places for a u32 + unit

fn parseLine(reader: anytype) !u32 {
    const line = try reader.readUntilDelimiter(&line_buf, '\n');

    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip row name

    return try std.fmt.parseUnsigned(u32, tokens.next() orelse unreachable, 10);
}

pub fn main() !void {
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = writer.writer();

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (std.time.sleep(interval * std.time.ns_per_ms)) {
        const file = try std.fs.openFileAbsolute("/proc/meminfo", .{});
        defer file.close();
        var buffered = std.io.bufferedReader(file.reader());
        const reader = buffered.reader();

        const total: f32 = @floatFromInt(try parseLine(&reader)); // MemTotal
        try reader.skipUntilDelimiterOrEof('\n'); // MemFree
        const available: f32 = @floatFromInt(try parseLine(&reader)); // MemAvailable

        const percentage = 1 - available / total;
        try writePercentage(percentage, stdout);
        try stdout.writeByte(' ');
        try writeBar(percentage, colors, stdout);
        try stdout.writeByte('\n');
        try writer.flush();
    }
}
