/// Writes a vertical bar based on a value from 0 to 1 with Unicode characters U+2581 to U+2588.
pub fn writeBar(value: f32, writer: anytype) !void {
    try writer.writeAll("\xE2\x96");
    try writer.writeByte(0x81 + @floatToInt(u8, @round(@minimum(@maximum(value * 8, 0), 8))));
}
