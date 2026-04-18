const std = @import("std");

const key_value_separator = ": ";

var playing = false;

fn connect(alloc: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, client: *std.http.Client) !*std.http.Client.Connection {
    const connection = blk: {
        const port = if (env.get("MPD_PORT")) |port| try std.fmt.parseInt(u16, port, 10) else 6600;
        if (env.get("MPD_HOST")) |host| {
            break :blk try client.connectTcp(try .init(host), port, .plain);
        }
        if (env.get("XDG_RUNTIME_DIR")) |runtime_dir| {
            const path = try std.mem.concat(alloc, u8, &.{ runtime_dir, "/mpd/socket" });
            defer alloc.free(path);
            // if (client.connectUnix(path)) |conn| break :blk conn else |_| {}
        }
        // if (client.connectUnix("/run/mpd/socket")) |conn| break :blk conn else |_| {}
        break :blk try client.connectTcp(try .init("localhost"), port, .plain);
    };
    errdefer connection.destroy(io);
    const reply = try connection.reader().takeSentinel('\n');
    if (!std.mem.startsWith(u8, reply, "OK MPD ")) return error.MissingMpdReply;
    return connection;
}

fn printTime(writer: *std.Io.Writer, seconds: f32) !void {
    const minutes: u32 = @intFromFloat(seconds / 60);
    const seconds_wrapped: u32 = @intFromFloat(@mod(seconds, 60));
    try writer.print("{:0>1}:{:0>2}", .{ minutes, seconds_wrapped });
}

fn print(io: std.Io, conn: *std.http.Client.Connection) !void {
    var title_buffer = [_]u8{0} ** 1024;
    var artist_buffer = [_]u8{0} ** 1024;
    var file_buffer = [_]u8{0} ** 1024;
    var stdout_buffer: [1024]u8 = undefined;

    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var artist: ?[]const u8 = null;
    var title: ?[]const u8 = null;
    var file: ?[]const u8 = null;
    var elapsed: f32 = 0;
    var duration: f32 = 0;
    var state: []const u8 = undefined;
    try conn.writer().writeAll("command_list_begin\ncurrentsong\nstatus\ncommand_list_end\n");
    try conn.writer().flush();
    while (conn.reader().takeSentinel('\n')) |line| {
        if (std.mem.eql(u8, line, "OK")) break else if (std.mem.startsWith(u8, line, "ACK")) {
            std.log.err("{s}", .{line});
            return error.MpdError;
        }
        var split = std.mem.splitSequence(u8, line, key_value_separator);
        const key = split.first();
        const val = split.rest();
        if (std.mem.eql(u8, key, "state")) {
            playing = std.mem.eql(u8, val, "play");
            state = val;
        } else if (std.mem.eql(u8, key, "file")) {
            @memcpy(file_buffer[0..val.len], val);
            file = file_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "Artist")) {
            @memcpy(artist_buffer[0..val.len], val);
            artist = artist_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "Title")) {
            @memcpy(title_buffer[0..val.len], val);
            title = title_buffer[0..val.len];
        } else if (std.mem.eql(u8, key, "elapsed")) {
            elapsed = try std.fmt.parseFloat(f32, val);
        } else if (std.mem.eql(u8, key, "duration")) {
            duration = try std.fmt.parseFloat(f32, val);
        }
    } else |err| return err;
    if (!std.mem.eql(u8, state, "stop")) {
        if (artist) |a| try stdout.print("{s} - ", .{a});
        try stdout.writeAll(title orelse std.fs.path.basename(file orelse ""));
        try stdout.writeAll(" [");
        try printTime(stdout, elapsed);
        try stdout.writeByte('/');
        try printTime(stdout, duration);
        try stdout.writeAll("]\n");
        try stdout.flush();
    }
}

fn interval(io: std.Io, connection: *std.http.Client.Connection) !void {
    while (true) {
        if (playing) try print(io, connection) else {
            try connection.writer().writeAll("ping\n");
            try connection.writer().flush();
            if (connection.reader().takeSentinel('\n')) |line| {
                if (!std.mem.eql(u8, line, "OK")) {
                    std.log.err("{s}", .{line});
                    return error.MpdError;
                }
            } else |err| return err;
        }
        try io.sleep(.fromSeconds(1), .awake);
    }
}

pub fn main(init: std.process.Init) !void {
    var client = std.http.Client{ .allocator = init.gpa, .io = init.io };
    defer client.deinit();

    const conn = try connect(init.gpa, init.io, init.environ_map, &client);
    defer conn.destroy(init.io);
    try print(init.io, conn);
    var interval_task = try init.io.concurrent(interval, .{ init.io, conn });
    defer interval_task.cancel(init.io) catch {};

    const conn2 = try connect(init.gpa, init.io, init.environ_map, &client);
    defer conn2.destroy(init.io);
    while (true) {
        try conn2.writer().writeAll("idle player\n");
        try conn2.writer().flush();
        while (conn2.reader().takeSentinel('\n')) |line| {
            if (std.mem.eql(u8, line, "OK")) break else if (std.mem.startsWith(u8, line, "ACK")) {
                std.log.err("{s}", .{line});
                return error.MpdError;
            }
        } else |err| return err;
        try print(init.io, conn2);
    }
}
