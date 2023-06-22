const std = @import("std");
const getColor = @import("color.zig").getColor;

/// Writes a vertical bar based on a value from 0 to 1 with Unicode characters U+2581 to U+2588.
pub fn writeBar(value: f32, colors: []u32, writer: anytype) !void {
    const color = getColor(@max(value, 0), colors);
    if (color) |c| try std.fmt.format(writer, "%{{F#{x:0>6}}}", .{c});
    try writer.writeAll("\xE2\x96");
    try writer.writeByte(0x81 + @intFromFloat(u8, @round(@min(@max(value * 8, 0), 8))));
    if (color) |_| try writer.writeAll("%{F-}");
}
