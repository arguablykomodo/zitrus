const std = @import("std");

pub const Format = enum {
    lemonbar,
    pango,
};

pub const fg = struct {
    pub fn start(writer: *std.Io.Writer, format: Format, color: u32) !void {
        switch (format) {
            .lemonbar => try writer.print("%{{F#{x:0>6}}}", .{color}),
            .pango => try writer.print("<span color=\"#{x:0>6}\">", .{color}),
        }
    }

    pub fn end(writer: *std.Io.Writer, format: Format) !void {
        switch (format) {
            .lemonbar => try writer.writeAll("%{F-}"),
            .pango => try writer.writeAll("</span>"),
        }
    }
};

pub const bg = struct {
    pub fn start(writer: *std.Io.Writer, format: Format, color: u32) !void {
        switch (format) {
            .lemonbar => try writer.print("%{{B#{x:0>6}}}", .{color}),
            .pango => try writer.print("<span bgcolor=\"#{x:0>6}\">", .{color}),
        }
    }

    pub fn end(writer: *std.Io.Writer, format: Format) !void {
        switch (format) {
            .lemonbar => try writer.writeAll("%{B-}"),
            .pango => try writer.writeAll("</span>"),
        }
    }
};

pub const clickAction = struct {
    pub fn start(writer: *std.Io.Writer, format: Format, action: []const u8) !void {
        switch (format) {
            .lemonbar => try writer.print("%{{A1:{s}:}}", .{action}),
            .pango => {},
        }
    }

    pub fn end(writer: *std.Io.Writer, format: Format) !void {
        switch (format) {
            .lemonbar => try writer.writeAll("%{A}"),
            .pango => {},
        }
    }
};
