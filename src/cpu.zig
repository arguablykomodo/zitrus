const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

const MAX_CORES = 64;
const LINE_COLUMNS = 10;

const CoreStat = struct {
    idle: u32,
    total: u32,
};

var stats = [_]CoreStat{.{ .total = 0, .idle = 0 }} ** MAX_CORES;
var line_buf: [4 + (1 + 10) * LINE_COLUMNS]u8 = undefined; // name + (space + u32) * columns

fn parseLine(reader: anytype, stat_i: std.math.IntFittingRange(0, MAX_CORES)) !f32 {
    const line = try reader.readUntilDelimiter(&line_buf, '\n');

    var tokens = std.mem.tokenize(u8, line, " ");
    _ = tokens.next(); // skip cpu name

    var stat = CoreStat{ .idle = undefined, .total = 0 };

    var i: std.math.IntFittingRange(0, LINE_COLUMNS - 1) = 0;
    while (tokens.next()) |token| : (i += 1) {
        const value = try std.fmt.parseUnsigned(u32, token, 10);
        stat.total += value;
        if (i == 3) {
            stat.idle = value;
        }
    }

    const new_idle: f32 = @floatFromInt(stat.idle - stats[stat_i].idle);
    const new_total: f32 = @floatFromInt(stat.total - stats[stat_i].total);
    const percentage = 1 - new_idle / new_total;
    stats[stat_i] = stat;
    return percentage;
}

pub fn main() !void {
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = writer.writer();

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (std.time.sleep(interval * std.time.ns_per_ms)) {
        const file = try std.fs.openFileAbsolute("/proc/stat", .{});
        defer file.close();
        var buffered = std.io.bufferedReader(file.reader());
        const reader = buffered.reader();

        const total = try parseLine(&reader, 0);
        try writePercentage(total, stdout);
        try stdout.writeByte(' ');

        var i: std.math.IntFittingRange(0, MAX_CORES) = 1;
        while ((try reader.readByte()) != 'i') : (i += 1) {
            const percentage = try parseLine(&reader, i);
            try writeBar(percentage, colors, stdout);
        }
        try stdout.writeByte('\n');
        try writer.flush();
    }
}
