const std = @import("std");
const fmt = std.fmt.comptimePrint;

const programs = .{ "cpu", "ram", "net", "bspwm", "mpd" };

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (programs) |name| {
        const exe = b.addExecutable(name, fmt("src/{s}.zig", .{name}));
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();
        const build_step = b.step(name, fmt("Build the `{s}` program", .{name}));
        build_step.dependOn(@ptrCast(*std.build.Step, exe.install_step.?));
    }
}
