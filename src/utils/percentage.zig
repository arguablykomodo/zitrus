const std = @import("std");

/// Writes a percentage value from 0 to 1.
pub fn writePercentage(value: f32, writer: anytype) !void {
    try std.fmt.format(writer, "{}%", .{@intFromFloat(std.math.IntFittingRange(0, 100), @round(@min(@max(value * 100, 0), 100)))});
}
