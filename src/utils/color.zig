const std = @import("std");

var color_buffer: [8]u32 = undefined;

pub fn parseColors(args: *std.process.Args.Iterator) ![]const u32 {
    var i: usize = 0;
    while (args.next()) |arg| : (i += 1) {
        if (i == color_buffer.len) break;
        color_buffer[i] = try std.fmt.parseUnsigned(u32, arg, 16);
    }
    return color_buffer[0..i];
}

pub fn getColor(value: f32, colors: []const u32) ?u32 {
    if (colors.len == 0) return null else if (colors.len == 1) return colors[0];

    const mapped = value * @as(f32, @floatFromInt(colors.len - 1));
    const i: usize = @intFromFloat(mapped);
    const c0 = colors[i];
    const c1 = colors[@min(i + 1, colors.len - 1)];
    const t = mapped - @floor(mapped);

    const r = lerp(c0 & 0xFF0000, c1 & 0xFF0000, t);
    const g = lerp(c0 & 0x00FF00, c1 & 0x00FF00, t);
    const b = lerp(c0 & 0x0000FF, c1 & 0x0000FF, t);
    return (r & 0xFF0000) + (g & 0x00FF00) + (b & 0x0000FF);
}

fn lerp(a: u32, b: u32, t: f32) u32 {
    return @intFromFloat((1 - t) * @as(f32, @floatFromInt(a)) + t * @as(f32, @floatFromInt(b)));
}
