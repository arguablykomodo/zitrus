const std = @import("std");
const getColor = @import("color.zig").getColor;
const markup = @import("markup.zig");

/// Writes a vertical bar based on a value from 0 to 1 with Unicode characters U+2581 to U+2588.
pub fn writeBar(writer: *std.Io.Writer, value: f32, colors: []const u32, format: markup.Format) !void {
    const color = getColor(@max(value, 0), colors);
    if (color) |c| try markup.fg.start(writer, format, c);
    try writer.writeAll("\xE2\x96");
    const offset: u8 = @intFromFloat(@round(@min(@max(value * 8, 0), 8)));
    try writer.writeByte(0x81 + offset);
    if (color) |_| try markup.fg.end(writer, format);
}
