const std = @import("std");

const programs = .{ "cpu", "ram", "net", "bspwm", "mpd", "pulseaudio" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    inline for (programs) |name| {
        const exe = b.addExecutable(.{
            .name = "zitrus-" ++ name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = if (std.mem.eql(u8, name, "pulseaudio")) blk: {
                    const translate_c = b.addTranslateC(.{
                        .root_source_file = b.path("src/pulseaudio.h"),
                        .target = target,
                        .optimize = optimize,
                    });
                    translate_c.linkSystemLibrary("libpulse", .{});
                    break :blk &.{.{
                        .name = "pulseaudioc",
                        .module = translate_c.createModule(),
                    }};
                } else &.{},
            }),
        });
        const install = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install.step);
        const build_step = b.step(name, "Build the `" ++ name ++ "` program");
        build_step.dependOn(&install.step);
    }
}
