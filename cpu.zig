const std = @import("std");
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

const MAX_CORES = 64;
const LINE_COLUMNS = 10;

// name + (space + u32) * columns
const MAX_LINE_LENGTH = 4 + (1 + 10) * LINE_COLUMNS;

const CoreStat = struct {
    idle: u32,
    total: u32,
};

var stats = [_]CoreStat{.{ .total = 0, .idle = 0 }} ** MAX_CORES;
var line_buf: [MAX_LINE_LENGTH]u8 = undefined;

fn parseLine(reader: *const std.fs.File.Reader, stat_i: std.math.IntFittingRange(0, MAX_CORES)) !f32 {
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

    const percentage = 1 - @intToFloat(f32, stat.idle - stats[stat_i].idle) / @intToFloat(f32, stat.total - stats[stat_i].total);
    stats[stat_i] = stat;
    return percentage;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    const interval = if (args.nextPosix()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;

    while (true) : (std.time.sleep(interval * 1000000)) {
        const file = try std.fs.openFileAbsolute("/proc/stat", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        const total = try parseLine(&reader, 0);
        try writePercentage(total, stdout);
        try stdout.writeByte(' ');

        var i: std.math.IntFittingRange(0, MAX_CORES) = 1;
        while ((try reader.readByte()) != 'i') : (i += 1) {
            const percentage = try parseLine(&reader, i);
            try writeBar(percentage, stdout);
        }
        try stdout.writeByte('\n');
    }
}
