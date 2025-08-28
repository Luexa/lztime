const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = blk: {
        const test_filter = b.option([]const u8, "test-filter", "Filter the tests to be executed");
        var filter_iterator = std.mem.splitScalar(u8, test_filter orelse break :blk &.{}, ',');
        var test_filters: std.ArrayListUnmanaged([]const u8) = .{};
        defer test_filters.deinit(b.allocator);
        while (filter_iterator.next()) |filter| {
            try test_filters.append(b.allocator, filter);
        }
        break :blk try test_filters.toOwnedSlice(b.allocator);
    };

    const lztime_module = b.addModule("lztime", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lztime_unit_tests = b.addTest(.{
        .root_module = lztime_module,
        .filters = test_filters,
    });
    const run_lztime_unit_tests = b.addRunArtifact(lztime_unit_tests);

    b.top_level_steps.clearRetainingCapacity();
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lztime_unit_tests.step);
    b.default_step = test_step;
}
