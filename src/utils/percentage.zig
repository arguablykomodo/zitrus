const std = @import("std");

/// Writes a percentage value from 0 to 1.
pub fn writePercentage(value: f32, writer: anytype) !void {
    try std.fmt.format(writer, "{}%", .{@as(u8, @intFromFloat(@round(@min(@max(value * 100, 0), 100))))});
}
