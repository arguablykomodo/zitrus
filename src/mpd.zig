const std = @import("std");

const key_value_separator = ": ";

threadlocal var line_buffer = [_]u8{0} ** 1024;
var title_buffer = [_]u8{0} ** 1024;
var artist_buffer = [_]u8{0} ** 1024;
var file_buffer = [_]u8{0} ** 1024;

var line_lock = std.Thread.Mutex{};
var playing = false;

threadlocal var mpd_reader: std.io.BufferedReader(4096, std.net.Stream.Reader) = undefined;
threadlocal var mpd_writer: std.net.Stream.Writer = undefined;

fn connect(alloc: std.mem.Allocator) !std.net.Stream {
    const stream = blk: {
        const port = if (std.os.getenv("MPD_PORT")) |port| try std.fmt.parseInt(u16, port, 10) else 6600;
        if (std.os.getenv("MPD_HOST")) |host| {
            if (std.net.tcpConnectToHost(alloc, host, port)) |stream| break :blk stream else |_| {}
        }
        if (std.os.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
            const path = try std.mem.concat(alloc, u8, &.{ runtime_dir, "/mpd/socket" });
            defer alloc.free(path);
            if (std.net.connectUnixSocket(path)) |stream| break :blk stream else |_| {}
        }
        if (std.net.connectUnixSocket("/run/mpd/socket")) |stream| break :blk stream else |_| {}
        break :blk try std.net.tcpConnectToHost(alloc, "localhost", port);
    };
    mpd_reader = std.io.bufferedReader(stream.reader());
    mpd_writer = stream.writer();
    const reply = try mpd_reader.reader().readUntilDelimiter(&line_buffer, '\n');
    if (!std.mem.startsWith(u8, reply, "OK MPD ")) return error.MissingMpdReply;
    return stream;
}

fn timeFormatter(seconds: f32, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("{:0>1}:{:0>2}", .{ @floatToInt(u32, seconds / 60), @floatToInt(u6, @mod(seconds, 60)) });
}

fn fmtTime(seconds: f32) std.fmt.Formatter(timeFormatter) {
    return .{ .data = seconds };
}

fn print() !void {
    line_lock.lock();
    defer line_lock.unlock();
    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout_writer = stdout.writer();
    var artist: ?[]const u8 = null;
    var title: ?[]const u8 = null;
    var file: ?[]const u8 = null;
    var elapsed: f32 = 0;
    var duration: f32 = 0;
    try mpd_writer.writeAll("command_list_begin\ncurrentsong\nstatus\ncommand_list_end\n");
    while (try mpd_reader.reader().readUntilDelimiterOrEof(&line_buffer, '\n')) |line| {
        if (std.mem.eql(u8, line, "OK")) break else if (std.mem.startsWith(u8, line, "ACK")) {
            std.log.err("{s}", .{line});
            return error.MpdError;
        }
        var split = std.mem.split(u8, line, key_value_separator);
        const key = split.first();
        const val = split.rest();
        if (std.mem.eql(u8, key, "state")) {
            playing = std.mem.eql(u8, val, "play");
        } else if (std.mem.eql(u8, key, "file")) {
            std.mem.copy(u8, &file_buffer, val);
            file = file_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "Artist")) {
            std.mem.copy(u8, &artist_buffer, val);
            artist = artist_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "Title")) {
            std.mem.copy(u8, &title_buffer, val);
            title = title_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "elapsed")) {
            elapsed = try std.fmt.parseFloat(f32, val);
        } else if (std.mem.eql(u8, key, "duration")) {
            duration = try std.fmt.parseFloat(f32, val);
        }
    }
    if (artist) |a| try stdout_writer.print("{s} - ", .{a});
    try stdout_writer.writeAll(if (title) |t| t else std.fs.path.basename(file.?));
    try stdout_writer.print(" [{}/{}]\n", .{ fmtTime(elapsed), fmtTime(duration) });
    try stdout.flush();
}

fn interval() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stream = try connect(allocator);
    defer stream.close();

    while (true) {
        if (playing) try print() else {
            try mpd_writer.writeAll("ping\n");
            if (try mpd_reader.reader().readUntilDelimiterOrEof(&line_buffer, '\n')) |line| {
                if (!std.mem.eql(u8, line, "OK")) {
                    std.log.err("{s}", .{line});
                    return error.MpdError;
                }
            } else return error.MpdError;
        }
        std.time.sleep(1000 * std.time.ns_per_ms);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stream = try connect(allocator);
    defer stream.close();

    try print();
    const interval_thread = try std.Thread.spawn(.{}, interval, .{});
    while (true) {
        try mpd_writer.writeAll("idle player\n");
        while (try mpd_reader.reader().readUntilDelimiterOrEof(&line_buffer, '\n')) |line| {
            if (std.mem.eql(u8, line, "OK")) break else if (std.mem.startsWith(u8, line, "ACK")) {
                std.log.err("{s}", .{line});
                return error.MpdError;
            }
        }
        try print();
    }
    interval_thread.join();
}
