const std = @import("std");

var BUFFER: [1024]u8 = undefined;

fn formatDesktop(writer: anytype, name: []const u8, focused: bool, focus_color: []const u8) !void {
    if (focused) try std.fmt.format(writer, "%{{B{s}}}", .{focus_color});
    try std.fmt.format(writer, " {s} %{{B-}}", .{name});
}

pub fn main() !void {
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = writer.writer();

    var args = std.process.args();
    _ = args.skip();
    const pipe_name = args.nextPosix() orelse return error.MissingPipeArgument;
    const monitor_name = args.nextPosix() orelse return error.MissingMonitorArgument;
    const focus_color = args.nextPosix() orelse "-";

    const pipe = (try std.fs.openFileAbsolute(pipe_name, .{ .read = true })).reader();

    while (true) {
        const input = try pipe.readUntilDelimiter(&BUFFER, '\n');

        const i = std.mem.indexOf(u8, input, monitor_name) orelse return error.MissingMonitor;
        var tokens = std.mem.tokenize(u8, input[(i + monitor_name.len)..], ":");
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
        try writer.flush();
    }
}
