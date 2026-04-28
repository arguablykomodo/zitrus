const std = @import("std");

fn formatDesktop(writer: *std.Io.Writer, name: []const u8, focused: bool, focus_color: []const u8) !void {
    if (focused) try writer.print("%{{B{s}}}", .{focus_color});
    try writer.print("%{{A1:bspc desktop -f {s}:}} {s} %{{A}}", .{ name, name });
    if (focused) try writer.writeAll("%{B-}");
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const monitor_name = args.next() orelse return error.MissingMonitorArgument;
    const focus_color = args.next() orelse "-";

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
                'o' => try formatDesktop(stdout, name, false, focus_color),
                'O', 'F', 'U' => try formatDesktop(stdout, name, true, focus_color),
                else => {},
            }
        }

        _ = try stdout.writeByte('\n');
        try stdout.flush();
    }
}
