const std = @import("std");
const markup = @import("utils/markup.zig");

fn formatDesktop(writer: *std.Io.Writer, name: []const u8, focused: bool, focus_color: u32, format: markup.Format) !void {
    if (focused) try markup.bg.start(writer, format, focus_color);
    var action_buf: [64]u8 = undefined;
    var action_writer = std.Io.Writer.fixed(&action_buf);
    try action_writer.print("bspc desktop -f {s}", .{name});
    try markup.clickAction.start(writer, format, action_writer.buffered());
    try writer.print(" {s} ", .{name});
    try markup.clickAction.end(writer, format);
    if (focused) try markup.bg.end(writer, format);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const format: @import("utils/markup.zig").Format = if (init.environ_map.contains("MARKUP_FORMAT_PANGO")) .pango else .lemonbar;
    var args = init.minimal.args.iterate();
    _ = args.skip();
    const monitor_name = args.next() orelse return error.MissingMonitorArgument;
    const focus_color = try std.fmt.parseUnsigned(u32, args.next() orelse return error.MissingFocusColor, 16);

    var process = try std.process.spawn(init.io, .{
        .argv = &.{ "bspc", "subscribe", "report" },
        .stdout = .pipe,
    });
    defer process.kill(init.io);
    var report_buffer: [1024]u8 = undefined;
    var reader = process.stdout.?.reader(init.io, &report_buffer);

    while (true) {
        const input = try reader.interface.takeSentinel('\n');

        const i = std.mem.indexOf(u8, input, monitor_name) orelse return error.MissingMonitor;
        var tokens = std.mem.tokenizeScalar(u8, input[(i + monitor_name.len)..], ':');
        while (tokens.next()) |token| {
            if (token[0] == 'L') break;
            const name = token[1..];
            switch (token[0]) {
                'o' => try formatDesktop(stdout, name, false, focus_color, format),
                'O', 'F', 'U' => try formatDesktop(stdout, name, true, focus_color, format),
                else => {},
            }
        }

        _ = try stdout.writeByte('\n');
        try stdout.flush();
    }
}
