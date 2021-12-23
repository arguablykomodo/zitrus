const std = @import("std");

const Context = struct {
    slice: []u8,
    index: *usize,
};

pub const Error = error{Overflow};

fn write(context: Context, bytes: []const u8) Error!usize {
    if (bytes.len > (context.slice.len - context.index.*)) return Error.Overflow;
    std.mem.copy(u8, context.slice[context.index.*..], bytes);
    context.index.* += bytes.len;
    return bytes.len;
}

pub const SliceWriter = std.io.Writer(Context, Error, write);

pub fn writer(slice: []u8, index: *usize) SliceWriter {
    return .{ .context = .{ .slice = slice, .index = index } };
}
