const std = @import("std");

const Build = std.Build;

pub fn build(builder: *Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const test_filter = builder.option([]const u8, "test-filter", "Filter the tests to be executed");

    const lztime_module = builder.addModule("lztime", .{
        .source_file = .{ .path = "src/lztime.zig" },
    });

    const test_artifact = builder.addTest(.{
        .root_source_file = lztime_module.source_file,
        .target = target,
        .optimize = optimize,
        .filter = test_filter,
    });

    const test_run_step = builder.addRunArtifact(test_artifact);

    builder.top_level_steps.clearRetainingCapacity();
    const test_step = builder.step("test", "Run library tests");
    test_step.dependOn(&test_run_step.step);
    builder.default_step = test_step;
}
