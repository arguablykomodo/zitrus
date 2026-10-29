const std = @import("std");
const goose = @import("goose");
const GStr = goose.core.value.GStr;
const Dict = std.StringHashMap(goose.core.value.GVariant);

const Player = struct {
    alloc: std.mem.Allocator,
    io: std.Io,

    name: [:0]const u8,
    unique_name: [:0]const u8,
    last_update: std.Io.Timestamp,

    playback_status: enum { playing, paused, stopped } = .stopped,
    loop_status: enum { none, track, playlist } = .none,
    rate: f64 = 1.0,
    shuffle: bool = false,
    position: i64 = 0,

    trackid: ?[]const u8 = null,
    length: ?i64 = null,
    title: ?[]const u8 = null,
    artist: ?[]const u8 = null,

    pub fn init(conn: *goose.Connection, name: [:0]const u8, unique_name: [:0]const u8) !Player {
        var player = Player{
            .alloc = conn.__allocator,
            .io = conn.io,
            .name = name,
            .unique_name = unique_name,
            .last_update = std.Io.Clock.awake.now(conn.io),
        };

        const prop_proxy = goose.proxy.Proxy.init(conn, name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties");
        var props_result = try prop_proxy.call("GetAll", .{GStr.new("org.mpris.MediaPlayer2.Player")});
        defer props_result.deinit();
        const props = try props_result.expectAlloc(Dict);
        try player.updateProperties(props);

        return player;
    }

    pub fn deinit(self: *Player) void {
        if (self.trackid) |trackid| self.alloc.free(trackid);
        if (self.title) |title| self.alloc.free(title);
        if (self.artist) |artist| self.alloc.free(artist);
        self.alloc.free(self.name);
        self.alloc.free(self.unique_name);
    }

    pub fn updatePosition(self: *Player) void {
        const now = std.Io.Clock.awake.now(self.io);
        const elapsed = self.last_update.durationTo(now);
        self.position += @intFromFloat(@as(f64, @floatFromInt(elapsed.toMicroseconds())) * self.rate);
        self.last_update = now;
    }

    pub fn setPosition(self: *Player, new_positon: i64) void {
        self.position = new_positon;
        self.last_update = std.Io.Clock.awake.now(self.io);
    }

    pub fn updateProperties(self: *Player, properties: Dict) !void {
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

    pub fn updateMetadata(self: *Player, metadata: Dict) !void {
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

    pub fn print(self: Player) !void {
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
        if (hours > 0)
            try writer.print("{}:{:0>2}:", .{ hours, @mod(minutes, 60) })
        else
            try writer.print("{}:", .{@mod(minutes, 60)});
        try writer.print("{:0>2}", .{@mod(seconds, 60)});
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

const State = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    conn: *goose.Connection,

    players: std.ArrayList(Player),
    active: ?usize = null,

    pub fn init(alloc: std.mem.Allocator, io: std.Io, conn: *goose.Connection) !State {
        return State{
            .alloc = alloc,
            .io = io,
            .conn = conn,
            .players = try std.ArrayList(Player).initCapacity(alloc, 1),
        };
    }

    pub fn deinit(self: *State) void {
        for (self.players.items) |*player| player.deinit();
        self.players.deinit(self.alloc);
    }

    pub fn addPlayer(self: *State, name: [:0]const u8, unique_name: [:0]const u8) !void {
        try self.players.append(self.alloc, try Player.init(self.conn, name, unique_name));
    }

    pub fn removePlayer(self: *State, unique_name: [:0]const u8) void {
        if (self.findPlayer(unique_name)) |i| {
            self.players.items[i].deinit();
            _ = self.players.swapRemove(i);
        }
    }

    pub fn findPlayer(self: *const State, unique_name: [:0]const u8) ?usize {
        return for (self.players.items, 0..) |player, i| {
            if (std.mem.eql(u8, player.unique_name, unique_name)) break i;
        } else null;
    }

    pub fn switchActive(self: *State, new_active: usize) !void {
        self.active = if (new_active >= self.players.items.len) null else new_active;
        if (self.active) |active| try self.players.items[active].print() else {
            var stdout_buffer: [1]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(self.io, &stdout_buffer);
            const writer = &stdout_writer.interface;
            try writer.writeByte('\n');
            try writer.flush();
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var conn = try goose.Connection.init(init.gpa, .Session, init.io, init.environ_map);
    defer conn.close();

    var state = try State.init(init.gpa, init.io, &conn);
    defer state.deinit();

    const dbus_proxy = goose.proxy.Proxy.init(&conn, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
    var names_result = try dbus_proxy.call("ListNames", .{});
    defer names_result.deinit();
    const names = try names_result.expect([]const GStr);
    for (names) |name| if (std.mem.startsWith(u8, name.s, "org.mpris.MediaPlayer2.")) {
        var unique_name_result = try dbus_proxy.call("GetNameOwner", .{name});
        defer unique_name_result.deinit();
        const unique_name = try unique_name_result.expect(GStr);
        try state.addPlayer(
            try init.gpa.dupeSentinel(u8, name.s, 0),
            try init.gpa.dupeSentinel(u8, unique_name.s, 0),
        );
    };

    try conn.addMatch("type=signal,interface=org.freedesktop.DBus.Properties,path=/org/mpris/MediaPlayer2");
    try conn.addMatch("type=signal,interface=org.mpris.MediaPlayer2.Player");
    try conn.addMatch("type=signal,interface=org.freedesktop.DBus,member=NameOwnerChanged");
    try conn.registerSignalHandler("org.freedesktop.DBus", "NameOwnerChanged", handleSignal, &state);
    try conn.registerSignalHandler("org.freedesktop.DBus.Properties", "PropertiesChanged", handleSignal, &state);
    try conn.registerSignalHandler("org.mpris.MediaPlayer2.Player", "Seeked", handleSignal, &state);

    var interval_task = try init.io.concurrent(interval, .{&state});
    defer interval_task.cancel(init.io) catch {};

    try conn.serve();
}

fn interval(state: *State) !void {
    while (true) {
        const rate = if (state.active) |active| blk: {
            const player = &state.players.items[active];
            if (player.playback_status == .playing) {
                player.updatePosition();
                try player.print();
            }
            break :blk player.rate;
        } else 1;
        try state.io.sleep(.fromMicroseconds(@intFromFloat(std.time.us_per_s / @max(1, rate))), .awake);
    }
}

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

    if (std.mem.eql(u8, member, "PropertiesChanged")) {
        const player = state.findPlayer(sender) orelse return;
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        _ = decoder.decode(GStr) catch unreachable;
        const props = decoder.decodeAlloc(Dict) catch unreachable;
        state.players.items[player].updateProperties(props) catch unreachable;
        state.switchActive(player) catch unreachable;
    } else if (std.mem.eql(u8, member, "Seeked")) {
        const player = state.findPlayer(sender) orelse return;
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        const time = decoder.decode(i64) catch unreachable;
        state.players.items[player].setPosition(time);
        state.switchActive(player) catch unreachable;
    } else if (std.mem.eql(u8, member, "NameOwnerChanged")) {
        var decoder = goose.message.BodyDecoder.fromMessage(state.alloc, msg);
        const name = decoder.decode(GStr) catch unreachable;
        _ = decoder.decode(GStr) catch unreachable;
        const new_owner = decoder.decode(GStr) catch unreachable;
        if (state.findPlayer(name.s)) |_| {
            if (new_owner.s.len == 0) state.removePlayer(name.s);
            state.switchActive(state.players.items.len -| 1) catch unreachable;
        } else if (std.mem.startsWith(u8, name.s, "org.mpris.MediaPlayer2.") and new_owner.s.len != 0) {
            state.addPlayer(
                state.alloc.dupeSentinel(u8, name.s, 0) catch unreachable,
                state.alloc.dupeSentinel(u8, new_owner.s, 0) catch unreachable,
            ) catch unreachable;
            state.switchActive(state.players.items.len -| 1) catch unreachable;
        }
    }
}
