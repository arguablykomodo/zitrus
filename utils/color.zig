const std = @import("std");

const MAX_COLORS = 8;
const ColorI = std.math.IntFittingRange(0, MAX_COLORS);

var color_buffer: [MAX_COLORS]u32 = undefined;

pub fn parseColors(args: *std.process.ArgIterator) ![]u32 {
    var i: ColorI = 0;
    while (args.nextPosix()) |arg| : (i += 1) {
        if (i == MAX_COLORS) break;
        color_buffer[i] = try std.fmt.parseUnsigned(u32, arg, 16);
    }
    return color_buffer[0..i];
}

pub fn getColor(value: f32, colors: []u32) ?u32 {
    if (colors.len == 0) return null
    else if (colors.len == 1) return colors[0];

    const mapped = value * @intToFloat(f32, colors.len - 1);
    const i = @floatToInt(ColorI, mapped);
    const c0 = colors[i];
    const c1 = colors[@minimum(i + 1, colors.len - 1)];
    const t = mapped - @floor(mapped);

    const r = lerp(c0 & 0xFF0000, c1 & 0xFF0000, t);
    const g = lerp(c0 & 0x00FF00, c1 & 0x00FF00, t);
    const b = lerp(c0 & 0x0000FF, c1 & 0x0000FF, t);
    return (r & 0xFF0000) + (g & 0x00FF00) + (b & 0x0000FF);
}

fn lerp(a: u32, b: u32, t: f32) u32 {
    return @floatToInt(u32, (1 - t) * @intToFloat(f32, a) + t * @intToFloat(f32, b));
}
