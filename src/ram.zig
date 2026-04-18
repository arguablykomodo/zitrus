const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

var line_buf: [16 + 10 + 3]u8 = undefined; // row name + places for a u32 + unit
var stdout_buffer: [1024]u8 = undefined;

fn parseLine(reader: *std.Io.Reader) !u32 {
    const line = try reader.takeSentinel('\n');

    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    _ = tokens.next(); // skip row name

    return try std.fmt.parseUnsigned(u32, tokens.next() orelse unreachable, 10);
}

pub fn main(init: std.process.Init) !void {
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (try init.io.sleep(.fromMilliseconds(@intCast(interval)), .awake)) {
        const file = try std.Io.Dir.openFileAbsolute(init.io, "/proc/meminfo", .{});
        defer file.close(init.io);
        var reader = file.reader(init.io, &line_buf);

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
