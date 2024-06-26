const std = @import("std");

var REPORT_BUFFER: [1024]u8 = undefined;
var PIPE_BUFFER: [256]u8 = undefined;

fn getPipe() ![]const u8 {
    var process = std.process.Child.init(&.{ "bspc", "subscribe", "-f", "report" }, std.heap.page_allocator);
    process.stdin_behavior = .Ignore;
    process.stdout_behavior = .Pipe;
    try process.spawn();
    const bytes_read = try process.stdout.?.readAll(&PIPE_BUFFER);
    switch (try process.wait()) {
        .Exited => |code| if (code != 0) return error.UnexpectedTerm,
        else => return error.UnexpectedTerm,
    }
    return PIPE_BUFFER[0 .. bytes_read - 1]; // Trim newline
}

fn formatDesktop(writer: anytype, name: []const u8, focused: bool, focus_color: []const u8) !void {
    if (focused) try std.fmt.format(writer, "%{{B{s}}}", .{focus_color});
    try std.fmt.format(writer, "%{{A1:bspc desktop -f {s}:}} {s} %{{A}}", .{ name, name });
    if (focused) try writer.writeAll("%{B-}");
}

pub fn main() !void {
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = writer.writer();

    var args = std.process.args();
    _ = args.skip();
    const monitor_name = args.next() orelse return error.MissingMonitorArgument;
    const focus_color = args.next() orelse "-";

    const pipe = try std.fs.openFileAbsolute(try getPipe(), .{});
    defer pipe.close();
    var buffered = std.io.bufferedReader(pipe.reader());
    const reader = buffered.reader();

    while (true) {
        const input = try reader.readUntilDelimiter(&REPORT_BUFFER, '\n');

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
