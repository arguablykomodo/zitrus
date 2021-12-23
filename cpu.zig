const std = @import("std");
const writer = @import("utils/slice_writer.zig").writer;

const MAX_CORES = 64;
const LINE_COLUMNS = 10;

// cpu name, plus (a space + decimal places for a u32) times columns
const MAX_LINE_LENGTH = 4 + (1 + 10) * LINE_COLUMNS;
// percentage, plus percentage sign, plus a space, plus block element length times max cores
const MAX_OUT_LENGTH = 3 + 1 + 1 + 3 * (MAX_CORES - 1);

const INTERVAL = 1000000000;

const CoreStat = struct {
    idle: u32,
    total: u32,
};

var stats = [_]CoreStat{.{ .total = 0, .idle = 0 }} ** MAX_CORES;
var line_buf: [MAX_LINE_LENGTH]u8 = undefined;
var out_buf: [MAX_OUT_LENGTH]u8 = undefined;

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
    const stdout = std.io.getStdOut();
    while (true) : (std.time.sleep(INTERVAL)) {
        const file = try std.fs.openFileAbsolute("/proc/stat", .{ .read = true });
        defer file.close();
        const reader = file.reader();

        var index: usize = 0;
        const out_writer = writer(out_buf[0..], &index);

        const total = try parseLine(&reader, 0);
        try std.fmt.formatInt(@floatToInt(std.math.IntFittingRange(0, 100), @round(total * 100)), 10, .lower, .{}, out_writer);
        try out_writer.writeAll("% ");

        var i: std.math.IntFittingRange(0, MAX_CORES) = 1;
        while ((try reader.readByte()) != 'i') : (i += 1) {
            const percentage = try parseLine(&reader, i);
            try out_writer.writeAll("\xE2\x96");
            try out_writer.writeByte(0x81 + @floatToInt(u8, @floor(8 * percentage)));
        }
        try out_writer.writeAll("\n\x00");

        try stdout.writeAll(out_buf[0..index]);
    }
}
