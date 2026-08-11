const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;
const Dict = std.StringHashMap(goose.core.value.GVariant);

const State = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    conn: *goose.Connection,

    name: ?[:0]const u8 = null,
    playback_status: enum { playing, paused, stopped } = .stopped,
    loop_status: enum { none, track, playlist } = .none,
    rate: f64 = 1.0,
    shuffle: bool = false,
    position: i64 = 0,
    last_update: std.Io.Timestamp = undefined,

    trackid: ?[]const u8 = null,
    length: ?i64 = null,
    title: ?[]const u8 = null,
    artist: ?[]const u8 = null,

    pub fn updatePosition(self: *State) void {
        const now = std.Io.Clock.awake.now(self.io);
        const elapsed = self.last_update.durationTo(now);
        self.position += @intFromFloat(@as(f64, @floatFromInt(elapsed.toMicroseconds())) * self.rate);
        self.last_update = now;
    }

    pub fn setPosition(self: *State, new_positon: i64) void {
        self.position = new_positon;
        self.last_update = std.Io.Clock.awake.now(self.io);
    }

    pub fn updateProxy(self: *State, name: [:0]const u8) !void {
        if (self.name) |n| self.alloc.free(n);
        self.name = name;

        self.playback_status = .stopped;
        self.loop_status = .none;
        self.rate = 1.0;
        self.shuffle = false;
        self.setPosition(0);
        self.trackid = null;
        self.length = null;
        self.title = null;
        self.artist = null;

        const prop_proxy = goose.proxy.Proxy.init(self.conn, name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties");
        var props_result = try prop_proxy.call("GetAll", .{GStr.new("org.mpris.MediaPlayer2.Player")});
        defer props_result.deinit();
        const props = try props_result.expectAlloc(Dict);
        try self.updateProperties(props);
    }

    pub fn updateProperties(self: *State, properties: Dict) !void {
        if (properties.get("PlaybackStatus")) |status| {
            const previous_status = self.playback_status;
            self.playback_status = if (std.mem.eql(u8, status.string.s, "Playing"))
                .playing
            else if (std.mem.eql(u8, status.string.s, "Paused"))
                .paused
            else if (std.mem.eql(u8, status.string.s, "Stopped"))
                .stopped
            else
                return error.InvalidPlaybackStatus;
            if (previous_status == .playing) self.updatePosition() else self.last_update = std.Io.Clock.awake.now(self.io);
        }
        if (properties.get("LoopStatus")) |status| {
            self.loop_status = if (std.mem.eql(u8, status.string.s, "None"))
                .none
            else if (std.mem.eql(u8, status.string.s, "Track"))
                .track
            else if (std.mem.eql(u8, status.string.s, "Playlist"))
                .playlist
            else
                return error.InvalidLoopStatus;
        }
        if (properties.get("Rate")) |rate| self.rate = rate.double;
        if (properties.get("Shuffle")) |shuffle| self.shuffle = shuffle.boolean;
        if (properties.get("Metadata")) |metadata| try self.updateMetadata(metadata.dict);
        if (properties.get("Position")) |position| self.setPosition(position.int64);
    }

    pub fn updateMetadata(self: *State, metadata: Dict) !void {
        if (metadata.get("mpris:length")) |prop| self.length = prop.variant.int64;
        if (metadata.get("mpris:trackid")) |prop| {
            const new_trackid = try self.alloc.dupe(u8, prop.variant.object_path.s);
            if (self.trackid) |t| {
                if (!std.mem.eql(u8, t, new_trackid)) self.setPosition(0);
                self.alloc.free(t);
            }
            self.trackid = new_trackid;
        }
        if (metadata.get("xesam:title")) |prop| {
            if (self.title) |t| self.alloc.free(t);
            if (prop.variant.string.s.len == 0) {
                self.title = null;
            } else {
                self.title = try self.alloc.dupe(u8, prop.variant.string.s);
            }
        }
        if (metadata.get("xesam:artist")) |prop| {
            if (prop.variant.array.len > 0) {
                if (self.artist) |a| self.alloc.free(a);
                if (prop.variant.array[0].string.s.len == 0) {
                    self.artist = null;
                } else {
                    self.artist = try self.alloc.dupe(u8, prop.variant.array[0].string.s);
                }
            } else self.artist = null;
        }
    }

    pub fn print(self: State) !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(self.io, &stdout_buffer);
        const writer = &stdout_writer.interface;

        switch (self.playback_status) {
            .playing => try writer.writeAll("\u{23F8}\u{FE0E}"),
            .paused => try writer.writeAll("\u{23F5}\u{FE0E}"),
            .stopped => return,
        }

        if (self.artist != null or self.title != null) try writer.writeAll(" ");
        if (self.artist) |a| try printTrimmed(writer, a, 20);
        if (self.artist != null and self.title != null) try writer.writeAll(" - ");
        if (self.title) |t| try printTrimmed(writer, t, 40);

        try writer.writeAll(" [");
        try printTime(writer, self.position);
        if (self.length) |l| if (l > 0) {
            try writer.writeByte('/');
            try printTime(writer, l);
        };
        try writer.writeAll("]");

        if (self.shuffle or self.loop_status != .none) try writer.writeAll(" ");
        if (self.shuffle) try writer.writeAll("\u{1F500}\u{FE0E}");
        switch (self.loop_status) {
            .none => {},
            .track => try writer.writeAll("\u{1F502}\u{FE0E}"),
            .playlist => try writer.writeAll("\u{1F501}\u{FE0E}"),
        }

        try writer.writeByte('\n');
        try writer.flush();
    }

    fn printTime(writer: *std.Io.Writer, time: i64) !void {
        const seconds = @as(u64, @intCast(time)) / std.time.us_per_s;
        const minutes = seconds / 60;
        const hours = minutes / 60;
        if (hours > 0) try writer.print("{}:", .{hours});
        try writer.print("{}:{:0>2}", .{ @mod(minutes, 60), @mod(seconds, 60) });
    }

    fn printTrimmed(writer: *std.Io.Writer, str: []const u8, max_len: usize) !void {
        var utf8 = (try std.unicode.Utf8View.init(str)).iterator();
        var chars: usize = 0;
        while (utf8.nextCodepointSlice()) |char| {
            try writer.writeAll(char);
            chars += 1;
            if (chars >= max_len) break;
        }
        if (utf8.nextCodepointSlice() != null) try writer.writeAll("\u{2026}");
    }
};

fn handleSignal(data: ?*anyopaque, msg: goose.core.Message) void {
    const state: *State = @ptrCast(@alignCast(data));

    var sender: [:0]const u8 = undefined;
    var member: [:0]const u8 = undefined;
    for (msg.header.header_fields) |field| {
        switch (field.value) {
            .Sender => |s| sender = s,
            .Member => |m| member = m,
            else => {},
        }
    }

    if (state.name == null or !std.mem.eql(u8, sender, state.name.?)) {
        state.updateProxy(state.alloc.dupeSentinel(u8, sender, 0) catch unreachable) catch unreachable;
    } else if (std.mem.eql(u8, member, "PropertiesChanged")) {
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        _ = decoder.decode(GStr) catch unreachable;
        const props = decoder.decodeAlloc(Dict) catch unreachable;
        state.updateProperties(props) catch unreachable;
    } else if (std.mem.eql(u8, member, "Seeked")) {
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        const time = decoder.decode(i64) catch unreachable;
        state.setPosition(time);
    }
    state.print() catch unreachable;
}

fn interval(io: std.Io, state: *State) !void {
    while (true) {
        if (state.playback_status == .playing) {
            state.updatePosition();
            try state.print();
        }
        try io.sleep(.fromMicroseconds(@intFromFloat(std.time.us_per_s / @max(1, state.rate))), .awake);
    }
}

pub fn main(init: std.process.Init) !void {
    var conn = try goose.Connection.init(init.gpa, .Session, init.io, init.environ_map);
    defer conn.close();

    var state = State{ .alloc = init.gpa, .io = init.io, .conn = &conn };

    {
        const dbus_proxy = goose.proxy.Proxy.init(&conn, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
        var names_result = try dbus_proxy.call("ListNames", .{});
        defer names_result.deinit();
        const names = try names_result.expect([]const GStr);
        for (names) |name| if (std.mem.startsWith(u8, name.s, "org.mpris.MediaPlayer2")) {
            var unique_name_result = try dbus_proxy.call("GetNameOwner", .{name});
            defer unique_name_result.deinit();
            const unique_name = try unique_name_result.expect(GStr);
            try state.updateProxy(try init.gpa.dupeSentinel(u8, unique_name.s, 0));
            break;
        };
    }

    try conn.addMatch("type=signal,interface=org.freedesktop.DBus.Properties,path=/org/mpris/MediaPlayer2");
    try conn.addMatch("type=signal,interface=org.mpris.MediaPlayer2.Player");
    try conn.registerSignalHandler("org.freedesktop.DBus.Properties", "PropertiesChanged", handleSignal, &state);
    try conn.registerSignalHandler("org.mpris.MediaPlayer2.Player", "Seeked", handleSignal, &state);

    var interval_task = try init.io.concurrent(interval, .{ init.io, &state });
    defer interval_task.cancel(init.io) catch {};

    while (true) {
        var msg = try conn.waitMessage();
        conn.freeMessage(&msg);
    }
}
