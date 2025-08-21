const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

var line_buf: [16 + 10 + 3]u8 = undefined; // row name + places for a u32 + unit
var stdout_buffer: [1024]u8 = undefined;

fn parseLine(reader: *std.Io.Reader) !u32 {
    const line = try reader.takeDelimiterExclusive('\n');

    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    _ = tokens.next(); // skip row name

    return try std.fmt.parseUnsigned(u32, tokens.next() orelse unreachable, 10);
}

pub fn main() !void {
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (std.Thread.sleep(interval * std.time.ns_per_ms)) {
        const file = try std.fs.openFileAbsolute("/proc/meminfo", .{});
        defer file.close();
        var reader = file.reader(&line_buf);

        const total: f32 = @floatFromInt(try parseLine(&reader.interface)); // MemTotal
        _ = try reader.interface.discardDelimiterInclusive('\n'); // MemFree
        const available: f32 = @floatFromInt(try parseLine(&reader.interface)); // MemAvailable

        const percentage = 1 - available / total;
        try writePercentage(stdout, percentage);
        try stdout.writeByte(' ');
        try writeBar(stdout, percentage, colors);
        try stdout.writeByte('\n');
        try stdout.flush();
    }
}
