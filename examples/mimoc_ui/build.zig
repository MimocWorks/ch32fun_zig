const std = @import("std");
const ch32 = @import("ch32fun_zig");

pub fn build(b: *std.Build) void {
    const target = ch32.ch32Target(b);
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;
    const ch32_dep = b.dependency("ch32fun_zig", .{});
    const mimoc_dep = b.dependency("mimoc_ui", .{ .target = target, .optimize = optimize });
    const hal = ch32.halModule(ch32_dep.builder);
    const options = b.addOptions();
    options.addOption(usize, "max_nodes", b.option(usize, "max_nodes", "Mimoc UI node capacity") orelse 8);
    options.addOption(usize, "max_animations", b.option(usize, "max_animations", "Mimoc UI animation capacity") orelse 1);

    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    app.addImport("ch32fun", hal);
    app.addImport("mimoc_ui", mimoc_dep.module("mimoc_ui"));
    app.addOptions("build_options", options);

    const startup = b.createModule(.{
        .root_source_file = ch32_dep.path("src/firmware.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    startup.addImport("app", app);
    startup.addImport("ch32fun", hal);

    const exe = b.addExecutable(.{ .name = "mimoc_ui_ch32v003", .root_module = startup, .linkage = .static });
    exe.bundle_compiler_rt = true;
    exe.link_gc_sections = true;
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    exe.setLinkerScript(ch32_dep.path("src/runtime/linker.ld"));
    b.installArtifact(exe);
    const bin = exe.addObjCopy(.{ .format = .bin, .basename = "mimoc_ui_ch32v003.bin" });
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(bin.getOutput(), .{ .custom = "firmware" }, "mimoc_ui_ch32v003.bin").step);
}
