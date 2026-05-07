const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;

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

    trackid: ?[]const u8 = null,
    length: ?i64 = null,
    title: ?[]const u8 = null,
    artist: ?[]const u8 = null,

    pub fn updateProxy(self: *State, name: [:0]const u8) !void {
        if (self.name) |n| self.alloc.free(n);
        self.name = name;

        self.playback_status = .stopped;
        self.loop_status = .none;
        self.rate = 1.0;
        self.shuffle = false;
        self.position = 0;
        self.trackid = null;
        self.length = null;
        self.title = null;
        self.artist = null;

        const prop_proxy = goose.proxy.Proxy.init(self.conn, name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties");
        var props_result = try prop_proxy.call("GetAll", .{GStr.new("org.mpris.MediaPlayer2.Player")});
        defer props_result.deinit();
        var prop_reader = props_result.reader();
        const props = try prop_reader.decode([]const DictEntry);
        try self.updateProperties(props);
    }

    pub fn updateProperties(self: *State, properties: []const DictEntry) !void {
        for (properties) |e| {
            if (std.mem.eql(u8, e.key.s, "PlaybackStatus")) {
                self.playback_status = if (std.mem.eql(u8, e.value.s.s, "Playing"))
                    .playing
                else if (std.mem.eql(u8, e.value.s.s, "Paused"))
                    .paused
                else if (std.mem.eql(u8, e.value.s.s, "Stopped"))
                    .stopped
                else
                    return error.InvalidPlaybackStatus;
            } else if (std.mem.eql(u8, e.key.s, "LoopStatus")) {
                self.loop_status = if (std.mem.eql(u8, e.value.s.s, "None"))
                    .none
                else if (std.mem.eql(u8, e.value.s.s, "Track"))
                    .track
                else if (std.mem.eql(u8, e.value.s.s, "Playlist"))
                    .playlist
                else
                    return error.InvalidLoopStatus;
            } else if (std.mem.eql(u8, e.key.s, "Rate")) {
                self.rate = e.value.d;
            } else if (std.mem.eql(u8, e.key.s, "Shuffle")) {
                self.shuffle = e.value.b;
            } else if (std.mem.eql(u8, e.key.s, "Metadata")) {
                try self.updateMetadata(e.value.e);
            } else if (std.mem.eql(u8, e.key.s, "Position")) {
                self.position = e.value.x;
            }
        }
    }

    pub fn updateMetadata(self: *State, metadata: []const DictEntry) !void {
        for (metadata) |entry| {
            if (std.mem.eql(u8, entry.key.s, "mpris:length")) {
                self.length = entry.value.x;
            } else if (std.mem.eql(u8, entry.key.s, "mpris:trackid")) {
                const new_trackid = try self.alloc.dupe(u8, entry.value.o.s);
                if (self.trackid) |t| {
                    if (!std.mem.eql(u8, t, new_trackid)) self.position = 0;
                    self.alloc.free(t);
                }
                self.trackid = new_trackid;
            } else if (std.mem.eql(u8, entry.key.s, "xesam:title")) {
                if (self.title) |t| self.alloc.free(t);
                if (entry.value.s.s.len == 0) {
                    self.title = null;
                } else {
                    self.title = try self.alloc.dupe(u8, entry.value.s.s);
                }
            } else if (std.mem.eql(u8, entry.key.s, "xesam:artist")) {
                if (entry.value.as.len > 0) {
                    if (self.artist) |a| self.alloc.free(a);
                    if (entry.value.as[0].s.len == 0) {
                        self.artist = null;
                    } else {
                        self.artist = try self.alloc.dupe(u8, entry.value.as[0].s);
                    }
                } else self.artist = null;
            }
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
        if (self.artist) |a| try fmtTrimmed(writer, a, 20);
        if (self.artist != null and self.title != null) try writer.writeAll(" - ");
        if (self.title) |t| try fmtTrimmed(writer, t, 40);

        try writer.writeAll(" [");
        const pos_s = @as(u64, @intCast(self.position)) / std.time.us_per_s;
        const pos_m = pos_s / 60;
        try writer.print("{}:{:0>2}", .{ pos_m, @mod(pos_s, 60) });
        if (self.length) |l| if (l > 0) {
            const len_s = @as(u64, @intCast(l)) / std.time.us_per_s;
            const len_m = len_s / 60;
            try writer.print("/{}:{:0>2}", .{ len_m, @mod(len_s, 60) });
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

    fn fmtTrimmed(writer: *std.Io.Writer, str: []const u8, max_len: usize) !void {
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

const Variant = union(enum) {
    as: []const GStr,
    b: bool,
    d: f64,
    e: []const DictEntry,
    i: i32,
    o: goose.core.value.GPath,
    s: GStr,
    t: u64,
    x: i64,
};

const DictEntry = struct {
    key: GStr,
    value: Variant,
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
        state.updateProxy(state.alloc.dupeZ(u8, sender) catch unreachable) catch unreachable;
    } else if (std.mem.eql(u8, member, "PropertiesChanged")) {
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        _ = decoder.decode(GStr) catch unreachable;
        const props = decoder.decode([]const DictEntry) catch unreachable;
        state.updateProperties(props) catch unreachable;
    } else if (std.mem.eql(u8, member, "Seeked")) {
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        const time = decoder.decode(i64) catch unreachable;
        state.position = time;
    }
    state.print() catch unreachable;
}

fn interval(io: std.Io, state: *State) !void {
    while (true) {
        if (state.playback_status == .playing) {
            try state.print();
            state.position += @intFromFloat(std.time.us_per_s * state.rate);
        }
        try io.sleep(.fromSeconds(1), .awake);
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
        var names_reader = names_result.reader();
        const names = try names_reader.decode([]const GStr);
        for (names) |name| if (std.mem.startsWith(u8, name.s, "org.mpris.MediaPlayer2")) {
            var unique_name_result = try dbus_proxy.call("GetNameOwner", .{name});
            defer unique_name_result.deinit();
            var unique_name_reader = unique_name_result.reader();
            const unique_name = try unique_name_reader.decode(GStr);
            try state.updateProxy(try init.gpa.dupeZ(u8, unique_name.s));
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
