const std = @import("std");

const programs = .{ "cpu", "ram", "net", "bspwm", "mpd", "pulseaudio" };

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (programs) |name| {
        const exe = b.addExecutable("zitrus-" ++ name, "src/" ++ name ++ ".zig");
        if (std.mem.eql(u8, name, "pulseaudio")) {
            exe.linkLibC();
            exe.linkSystemLibrary("libpulse");
        }
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();
        const build_step = b.step(name, "Build the `" ++ name ++ "` program");
        build_step.dependOn(@ptrCast(*std.build.Step, exe.install_step.?));
    }
}
