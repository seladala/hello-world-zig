// НЕ ВАЙБКОД ✅ Написано полностью вручную, без нейросетей.
// Каждая строка набрана лично на клавиатуре. Честно 🤝✅
//! Build graph: the `core` library module, the `hello-world` executable and
//! the test suite.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const project_root = b.build_root.handle.realpathAlloc(b.allocator, ".") catch
        @panic("cannot resolve the project root");
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "project_root", project_root);

    const core = b.addModule("core", .{
        .root_source_file = b.path("src/core/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "hello-world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "core", .module = core }},
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Print hello world").dependOn(&run.step);

    const test_options = b.addOptions();
    test_options.addOptionPath("exe_path", exe.getEmittedBin());
    test_options.addOption([]const u8, "project_root", project_root);
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_core.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "core", .module = core },
                .{ .name = "test_options", .module = test_options.createModule() },
            },
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the test suite").dependOn(&run_tests.step);
}
