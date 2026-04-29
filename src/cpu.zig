const std = @import("std");
const parseColors = @import("utils/color.zig").parseColors;
const writeBar = @import("utils/bar.zig").writeBar;
const writePercentage = @import("utils/percentage.zig").writePercentage;

const CoreStat = struct {
    idle: u32,
    total: u32,
};

fn parseLine(reader: *std.Io.Reader, stat: *CoreStat) !f32 {
    const line = try reader.takeSentinel('\n');

    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    _ = tokens.next(); // skip cpu name

    var new_stat = CoreStat{ .idle = 0, .total = 0 };

    var i: usize = 0;
    while (tokens.next()) |token| : (i += 1) {
        const value = try std.fmt.parseUnsigned(u32, token, 10);
        new_stat.total += value;
        if (i == 3 or i == 4) {
            new_stat.idle += value;
        }
    }

    const new_idle: f32 = @floatFromInt(new_stat.idle - stat.idle);
    const new_total: f32 = @floatFromInt(new_stat.total - stat.total);
    const percentage = 1 - new_idle / new_total;
    stat.* = new_stat;
    return percentage;
}

pub fn main(init: std.process.Init) !void {
    var stats = [_]CoreStat{.{ .total = 0, .idle = 0 }} ** 64;

    const format: @import("utils/markup.zig").Format = if (init.environ_map.contains("MARKUP_FORMAT_PANGO")) .pango else .lemonbar;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const interval = if (args.next()) |arg| try std.fmt.parseUnsigned(u64, arg, 10) else 1000;
    const colors = try parseColors(&args);

    while (true) : (try std.Io.sleep(init.io, .fromMilliseconds(@intCast(interval)), .awake)) {
        const file = try std.Io.Dir.openFileAbsolute(init.io, "/proc/stat", .{});
        defer file.close(init.io);
        var line_buf: [1024]u8 = undefined;
        var reader = file.reader(init.io, &line_buf);

        const total = try parseLine(&reader.interface, &stats[0]);
        try writePercentage(stdout, total);
        try stdout.writeByte(' ');

        var i: usize = 1;
        while ((try reader.interface.takeByte()) != 'i') : (i += 1) {
            const percentage = try parseLine(&reader.interface, &stats[i]);
            try writeBar(stdout, percentage, colors, format);
        }
        try stdout.writeByte('\n');
        try stdout.flush();
    }
}
