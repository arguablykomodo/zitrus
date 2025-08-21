const std = @import("std");

/// Writes a percentage value from 0 to 1.
pub fn writePercentage(writer: *std.Io.Writer, value: f32) !void {
    try writer.print("{}%", .{@as(u8, @intFromFloat(@round(@min(@max(value * 100, 0), 100))))});
}
