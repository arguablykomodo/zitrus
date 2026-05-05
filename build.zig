const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const programs = .{ .cpu, .ram, .net, .bspwm, .mpd, .pulseaudio, .mpris };
    inline for (programs) |name| {
        const exe = b.addExecutable(.{
            .name = "zitrus-" ++ @tagName(name),
            .use_llvm = switch (name) {
                .pulseaudio => true,
                else => false,
            },
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/" ++ @tagName(name) ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = switch (name) {
                    .pulseaudio => blk: {
                        const translate_c = b.addTranslateC(.{
                            .root_source_file = b.path("src/pulseaudio.h"),
                            .target = target,
                            .optimize = optimize,
                        });
                        translate_c.linkSystemLibrary("pulse", .{});
                        break :blk &.{.{
                            .name = "pulseaudioc",
                            .module = translate_c.createModule(),
                        }};
                    },
                    .mpris => blk: {
                        const goose_dep = b.dependency("goose", .{
                            .target = target,
                            .optimize = optimize,
                        });
                        break :blk &.{.{
                            .name = "goose",
                            .module = goose_dep.module("goose"),
                        }};
                    },
                    else => &.{},
                },
            }),
        });
        const install = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install.step);
        const build_step = b.step(@tagName(name), "Build the `" ++ @tagName(name) ++ "` program");
        build_step.dependOn(&install.step);
    }
}
