const std = @import("std");
const c = @import("pulseaudioc");

const State = struct {
    default_sink_id: ?u32,
    stdout_writer: std.Io.File.Writer,
};

fn check(status: c_int, comptime err: anyerror) !void {
    if (status < 0) {
        return err;
    }
}

fn sinkInfoCallback(
    context: ?*c.pa_context,
    info: ?*const c.pa_sink_info,
    eol: c_int,
    state_erased: ?*anyopaque,
) callconv(.c) void {
    if (eol > 0) return else if (eol < 0) std.process.exit(1);
    const state: *State = @ptrCast(@alignCast(state_erased));
    if (state.default_sink_id == null) {
        state.default_sink_id = info.?.index;
        c.pa_context_set_subscribe_callback(context, contextSubscribeCallback, state);
        c.pa_operation_unref(c.pa_context_subscribe(context, c.PA_SUBSCRIPTION_MASK_SINK, null, null));
    }
    const volume: f32 = @floatFromInt(c.pa_cvolume_avg(&info.?.volume));
    const normalized = volume * 100 / @as(f32, @floatFromInt(c.PA_VOLUME_NORM));
    const stdout = &state.stdout_writer.interface;
    stdout.print("{: >3}\n", .{@as(u8, @intFromFloat(@round(normalized)))}) catch std.process.exit(1);
    stdout.flush() catch std.process.exit(1);
}

fn contextSubscribeCallback(
    context: ?*c.pa_context,
    event: c.pa_subscription_event_type_t,
    idx: u32,
    state_erased: ?*anyopaque,
) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(state_erased));
    const event_type = event & c.PA_SUBSCRIPTION_EVENT_TYPE_MASK;
    if (event_type == c.PA_SUBSCRIPTION_EVENT_CHANGE and idx == state.default_sink_id.?) {
        c.pa_operation_unref(c.pa_context_get_sink_info_by_index(context, state.default_sink_id.?, sinkInfoCallback, state));
    }
}

fn serverInfoCallback(
    context: ?*c.pa_context,
    info: ?*const c.pa_server_info,
    state_erased: ?*anyopaque,
) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(state_erased));
    c.pa_operation_unref(c.pa_context_get_sink_info_by_name(context, info.?.default_sink_name, sinkInfoCallback, state));
}

fn contextStateCallback(context: ?*c.pa_context, state_erased: ?*anyopaque) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(state_erased));
    switch (c.pa_context_get_state(context)) {
        c.PA_CONTEXT_UNCONNECTED => {},
        c.PA_CONTEXT_CONNECTING => {},
        c.PA_CONTEXT_AUTHORIZING => {},
        c.PA_CONTEXT_SETTING_NAME => {},
        c.PA_CONTEXT_READY => {
            c.pa_operation_unref(c.pa_context_get_server_info(context, serverInfoCallback, state));
        },
        c.PA_CONTEXT_FAILED => {
            std.log.err("failed to connect to pulseaudio", .{});
            std.process.exit(1);
        },
        c.PA_CONTEXT_TERMINATED => {},
        else => unreachable,
    }
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var state = State{
        .default_sink_id = null,
        .stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer),
    };

    const mainloop = c.pa_mainloop_new() orelse return error.PulseMainloopNew;
    defer c.pa_mainloop_free(mainloop);

    const api = c.pa_mainloop_get_api(mainloop) orelse return error.PulseMainloopGetApi;

    const context = c.pa_context_new(api, "zitrus-pulseaudio") orelse return error.PulseContextNew;
    defer c.pa_context_disconnect(context);
    c.pa_context_set_state_callback(context, contextStateCallback, &state);

    try check(c.pa_context_connect(context, null, c.PA_CONTEXT_NOAUTOSPAWN, null), error.PulseContextConnect);

    var retval: c_int = 0;
    try check(c.pa_mainloop_run(mainloop, &retval), error.PulseMainloopRun);
}
