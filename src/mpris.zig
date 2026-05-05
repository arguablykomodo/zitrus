const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;

const PlaybackStatus = enum {
    playing,
    paused,
    stopped,

    pub fn from(str: []const u8) PlaybackStatus {
        return if (std.mem.eql(u8, str, "Playing"))
            .playing
        else if (std.mem.eql(u8, str, "Paused"))
            .paused
        else if (std.mem.eql(u8, str, "Stopped"))
            .stopped
        else
            unreachable;
    }
};

const LoopStatus = enum {
    none,
    track,
    playlist,

    pub fn from(str: []const u8) LoopStatus {
        return if (std.mem.eql(u8, str, "None"))
            .none
        else if (std.mem.eql(u8, str, "Track"))
            .track
        else if (std.mem.eql(u8, str, "Playlist"))
            .playlist
        else
            unreachable;
    }
};

const State = struct {
    alloc: std.mem.Allocator,
    io: std.Io,

    playback_status: PlaybackStatus = .stopped,
    loop_status: LoopStatus = .none,
    rate: f64 = 1.0,
    shuffle: bool = false,
    position: i64 = 0,

    trackid: ?[]const u8 = null,
    length: ?i64 = null,
    title: ?[]const u8 = null,
    artist: ?[]const u8 = null,

    pub fn updatePlayback(self: *State, new_status: PlaybackStatus) void {
        if (self.playback_status == .stopped and new_status == .playing) {
            self.position = 0;
        }
        self.playback_status = new_status;
    }

    pub fn updateMetadata(self: *State, metadata: []const DictEntry) void {
        for (metadata) |entry| {
            if (std.mem.eql(u8, entry.key.s, "mpris:length")) {
                self.length = entry.value.x;
            } else if (std.mem.eql(u8, entry.key.s, "mpris:trackid")) {
                const new_trackid = self.alloc.dupe(u8, entry.value.o.s) catch unreachable;
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
                    self.title = self.alloc.dupe(u8, entry.value.s.s) catch unreachable;
                }
            } else if (std.mem.eql(u8, entry.key.s, "xesam:artist")) {
                if (entry.value.as.len > 0) {
                    if (self.artist) |a| self.alloc.free(a);
                    if (entry.value.as[0].s.len == 0) {
                        self.artist = null;
                    } else {
                        self.artist = self.alloc.dupe(u8, entry.value.as[0].s) catch unreachable;
                    }
                } else self.artist = null;
            }
        }
    }

    pub fn print(self: State) !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(self.io, &stdout_buffer);
        try stdout_writer.interface.print("{f}\n", .{self});
        try stdout_writer.interface.flush();
    }

    pub fn format(self: State, writer: *std.Io.Writer) !void {
        switch (self.playback_status) {
            .playing => try writer.writeAll("\u{23F8}\u{FE0E}"),
            .paused => try writer.writeAll("\u{23F5}\u{FE0E}"),
            .stopped => try writer.writeAll("\u{23F9}\u{FE0E}"),
        }

        if (self.artist != null or self.title != null) try writer.writeAll(" ");
        if (self.artist) |a| try writer.writeAll(a);
        if (self.artist != null and self.title != null) try writer.writeAll(" - ");
        if (self.title) |t| try writer.writeAll(t);

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

fn onPropChange(data: ?*anyopaque, msg: goose.core.Message) void {
    const state: *State = @ptrCast(@alignCast(data));
    var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
    _ = decoder.decode(GStr) catch unreachable;
    const dict = decoder.decode([]const DictEntry) catch unreachable;
    for (dict) |e| {
        if (std.mem.eql(u8, e.key.s, "PlaybackStatus")) {
            state.playback_status = PlaybackStatus.from(e.value.s.s);
        } else if (std.mem.eql(u8, e.key.s, "LoopStatus")) {
            state.loop_status = LoopStatus.from(e.value.s.s);
        } else if (std.mem.eql(u8, e.key.s, "Rate")) {
            state.rate = e.value.d;
        } else if (std.mem.eql(u8, e.key.s, "Shuffle")) {
            state.shuffle = e.value.b;
        } else if (std.mem.eql(u8, e.key.s, "Metadata")) {
            state.updateMetadata(e.value.e);
        }
    }
    state.print() catch unreachable;
}

fn onSeek(data: ?*anyopaque, msg: goose.core.Message) void {
    const state: *State = @ptrCast(@alignCast(data));
    var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
    const time = decoder.decode(i64) catch unreachable;
    state.position = time;
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
    var state = State{ .alloc = init.gpa, .io = init.io };

    var conn = try goose.Connection.init(init.gpa, .Session, init.io, init.environ_map);
    defer conn.close();

    // const p = goose.proxy.Proxy.init(&conn, "org.mpris.MediaPlayer2", "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player");
    // state.playback_status = PlaybackStatus.from((try p.getProperty(GStr, "PlaybackStatus")).s);
    // state.loop_status = LoopStatus.from((try p.getProperty(GStr, "PlaybackStatus")).s);
    // state.rate = try p.getProperty(f64, "Rate");
    // state.shuffle = try p.getProperty(bool, "Shuffle");
    // state.position = try p.getProperty(i64, "Position");
    // state.updateMetadata(try p.getProperty([]const DictEntry, "Metadata"));

    try conn.addMatch("type=signal,interface=org.freedesktop.DBus.Properties,path_namespace=/org/mpris/MediaPlayer2");
    try conn.addMatch("type=signal,interface=org.mpris.MediaPlayer2.Player");
    try conn.registerSignalHandler("org.freedesktop.DBus.Properties", "PropertiesChanged", onPropChange, &state);
    try conn.registerSignalHandler("org.mpris.MediaPlayer2.Player", "Seeked", onSeek, &state);

    var interval_task = try init.io.concurrent(interval, .{ init.io, &state });
    defer interval_task.cancel(init.io) catch {};

    while (true) {
        var msg = try conn.waitMessage();
        conn.freeMessage(&msg);
    }
}
