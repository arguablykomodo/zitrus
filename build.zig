const std = @import("std");

const programs = .{ "cpu", "ram", "net", "bspwm", "mpd", "pulseaudio" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    inline for (programs) |name| {
        const exe = b.addExecutable(.{
            .name = "zitrus-" ++ name,
            .root_source_file = .{ .path = "src/" ++ name ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        if (std.mem.eql(u8, name, "pulseaudio")) {
            exe.linkLibC();
            exe.linkSystemLibrary("libpulse");
        }
        const install = b.addInstallArtifact(exe);
        b.getInstallStep().dependOn(&install.step);
        const build_step = b.step(name, "Build the `" ++ name ++ "` program");
        build_step.dependOn(&install.step);
    }
}
