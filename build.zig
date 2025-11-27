const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Library module (Tree Calculus core)
    //
    const lib = b.addModule("tree3", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    //
    // Executable using the library
    //
    const exe = b.addExecutable(.{
        .name = "tree3",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "tree3", .module = lib }},
        }),
    });

    b.installArtifact(exe);

    //
    // zig build run
    //
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| run_cmd.addArgs(args);

    //
    // zig build test  (tests inside src/root.zig)
    //
    const tests = b.addTest(.{
        .root_module = lib,
    });

    const test_cmd = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_cmd.step);
}
