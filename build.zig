const std = @import("std");

const Example = struct {
    name: []const u8,
    path: []const u8,
};

const examples = [_]Example{
    .{ .name = "blinky", .path = "examples/blinky/main.zig" },
    .{ .name = "gpio_input", .path = "examples/gpio_input/main.zig" },
    .{ .name = "timer_irq", .path = "examples/timer_irq/main.zig" },
    .{ .name = "oled", .path = "examples/oled/main.zig" },
    .{ .name = "persistent_counter", .path = "examples/persistent_counter/main.zig" },
    .{ .name = "uart_hello", .path = "examples/uart_hello/main.zig" },
    .{ .name = "led_fade", .path = "examples/led_fade/main.zig" },
    .{ .name = "tone_song", .path = "examples/tone_song/main.zig" },
    .{ .name = "adc_meter", .path = "examples/adc_meter/main.zig" },
    .{ .name = "exti_button", .path = "examples/exti_button/main.zig" },
    .{ .name = "compile_time_morse", .path = "examples/compile_time_morse/main.zig" },
    .{ .name = "state_machine_game", .path = "examples/state_machine_game/main.zig" },
    .{ .name = "packed_settings", .path = "examples/packed_settings/main.zig" },
    .{ .name = "comptime_lookup", .path = "examples/comptime_lookup/main.zig" },
    .{ .name = "spi_loopback", .path = "examples/spi_loopback/main.zig" },
    .{ .name = "uart_dma", .path = "examples/uart_dma/main.zig" },
    .{ .name = "ir_text", .path = "examples/ir_text/main.zig" },
};

fn resolveExample(name: []const u8) ?Example {
    inline for (examples) |example| {
        if (std.mem.eql(u8, name, example.name)) return example;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Reusable package API
//
// Other projects can depend on this package and build their own CH32V003
// firmware without copying the target/linker boilerplate:
//
//   // build.zig.zon
//   .dependencies = .{
//       .ch32fun_zig = .{ .path = "../ch32fun_zig" }, // or .url/.hash
//   },
//
//   // build.zig
//   const ch32 = @import("ch32fun_zig");
//   const dep = b.dependency("ch32fun_zig", .{});
//   const fw = ch32.addFirmware(b, dep, .{
//       .name = "my_app",
//       .root_source_file = b.path("src/main.zig"),
//       .optimize = .ReleaseSmall,
//   });
//   b.installArtifact(fw);
//
// The firmware's root module gets the `ch32fun` HAL import wired in
// automatically, and the chip's linker script is applied.
// ---------------------------------------------------------------------------

/// The CH32V003 target query (RV32EC, freestanding, EABI).
pub fn ch32Target(b: *std.Build) std.Build.ResolvedTarget {
    return b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{
            std.Target.riscv.Feature.c,
            std.Target.riscv.Feature.e,
        }),
        .cpu_features_sub = std.Target.riscv.featureSet(&.{
            std.Target.riscv.Feature.i,
        }),
        .os_tag = .freestanding,
        .abi = .eabi,
    });
}

/// The `ch32fun` HAL module, rooted in this package's source tree.
/// `pkg` must be the builder that owns this package's files: pass the
/// dependency's `.builder` when called from a downstream project, or `b`
/// itself when building inside this repo.
pub fn halModule(pkg: *std.Build) *std.Build.Module {
    return pkg.createModule(.{
        .root_source_file = pkg.path("src/ch32fun.zig"),
    });
}

pub const FirmwareOptions = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode = .ReleaseSmall,
    /// Override the default CH32V003 linker script.
    linker_script: ?std.Build.LazyPath = null,
};

/// Build a CH32V003 firmware executable with the HAL wired in.
///
/// `app_builder` is the caller's builder (where the artifact is installed);
/// `dep` is the resolved `ch32fun_zig` dependency, or `null` when building
/// inside this repo (HAL/linker resolve against `app_builder`).
pub fn addFirmware(
    app_builder: *std.Build,
    dep: ?*std.Build.Dependency,
    options: FirmwareOptions,
) *std.Build.Step.Compile {
    const pkg = if (dep) |d| d.builder else app_builder;

    const root_module = app_builder.createModule(.{
        .root_source_file = options.root_source_file,
        .target = ch32Target(app_builder),
        .optimize = options.optimize,
        .link_libc = false,
    });
    root_module.addImport("ch32fun", halModule(pkg));

    const exe = app_builder.addExecutable(.{
        .name = options.name,
        .root_module = root_module,
        .linkage = .static,
    });
    exe.bundle_compiler_rt = true;
    exe.link_gc_sections = true;
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    exe.setLinkerScript(options.linker_script orelse pkg.path("src/runtime/linker.ld"));

    return exe;
}

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode") orelse .ReleaseSmall;
    const example_name = b.option([]const u8, "example", "Example to build") orelse "blinky";
    const selected = resolveExample(example_name) orelse {
        std.debug.print("Unknown example '{s}'. Available: blinky, gpio_input, timer_irq, oled, persistent_counter, uart_hello, led_fade, tone_song, adc_meter, exti_button, compile_time_morse, state_machine_game, packed_settings, comptime_lookup, spi_loopback, uart_dma, ir_text\n", .{example_name});
        @panic("invalid example");
    };

    const mkdir_step = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/firmware" });

    // Build the selected example through the public package API so the two
    // paths can't drift (in-repo build === downstream `addFirmware`).
    const exe = addFirmware(b, null, .{
        .name = selected.name,
        .root_source_file = b.path(selected.path),
        .optimize = optimize,
    });
    exe.step.dependOn(&mkdir_step.step);

    b.installArtifact(exe);

    const elf_install = b.addInstallFileWithDir(exe.getEmittedBin(), .{ .custom = "firmware" }, b.fmt("{s}.elf", .{selected.name}));
    b.getInstallStep().dependOn(&elf_install.step);

    const bin = exe.addObjCopy(.{
        .format = .bin,
        .basename = b.fmt("{s}.bin", .{selected.name}),
    });
    const bin_install = b.addInstallFileWithDir(bin.getOutput(), .{ .custom = "firmware" }, b.fmt("{s}.bin", .{selected.name}));
    b.getInstallStep().dependOn(&bin_install.step);

    const hex = exe.addObjCopy(.{
        .format = .hex,
        .basename = b.fmt("{s}.hex", .{selected.name}),
    });
    const hex_install = b.addInstallFileWithDir(hex.getOutput(), .{ .custom = "firmware" }, b.fmt("{s}.hex", .{selected.name}));
    b.getInstallStep().dependOn(&hex_install.step);

    const lst_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if command -v llvm-objdump >/dev/null 2>&1; then llvm-objdump -d \"$1\" > \"$2\"; else riscv-none-elf-objdump -d \"$1\" > \"$2\"; fi",
        "sh",
    });
    lst_cmd.addFileArg(exe.getEmittedBin());
    const lst_file = lst_cmd.addOutputFileArg(b.fmt("{s}.lst", .{selected.name}));
    const lst_install = b.addInstallFileWithDir(lst_file, .{ .custom = "firmware" }, b.fmt("{s}.lst", .{selected.name}));
    lst_install.step.dependOn(&lst_cmd.step);

    const map_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if command -v llvm-nm >/dev/null 2>&1; then llvm-nm -n \"$1\" > \"$2\"; else riscv-none-elf-nm -n \"$1\" > \"$2\"; fi",
        "sh",
    });
    map_cmd.addFileArg(exe.getEmittedBin());
    const map_file = map_cmd.addOutputFileArg(b.fmt("{s}.map", .{selected.name}));
    const map_install = b.addInstallFileWithDir(map_file, .{ .custom = "firmware" }, b.fmt("{s}.map", .{selected.name}));
    map_install.step.dependOn(&map_cmd.step);

    const flash = b.step("flash", "Flash selected example using minichlink");
    flash.dependOn(b.getInstallStep());

    const flash_cmd = b.addSystemCommand(&.{ "sh", "tools/flash.sh" });
    flash_cmd.addArg(selected.name);
    flash_cmd.step.dependOn(b.getInstallStep());
    flash.dependOn(&flash_cmd.step);

    const disasm = b.step("disasm", "Generate disassembly (.lst) — requires llvm-objdump or riscv-none-elf-objdump");
    disasm.dependOn(&lst_install.step);

    const mapfile = b.step("mapfile", "Generate symbol map (.map) — requires llvm-nm or riscv-none-elf-nm");
    mapfile.dependOn(&map_install.step);

    const size_cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if command -v llvm-size >/dev/null 2>&1; then llvm-size \"$1\"; else riscv-none-elf-size \"$1\"; fi",
        "sh",
    });
    size_cmd.addFileArg(exe.getEmittedBin());
    size_cmd.step.dependOn(b.getInstallStep());
    const size = b.step("size", "Show firmware size — requires llvm-size or riscv-none-elf-size");
    size.dependOn(&size_cmd.step);

    // Build every example and print a size table. Falls back to raw .bin size
    // when no `size` tool is installed. Ignores -Dexample (it builds them all).
    const bench_cmd = b.addSystemCommand(&.{ "sh", "tools/size-benchmark.sh" });
    bench_cmd.addArg(@tagName(optimize));
    const benchmark = b.step("benchmark", "Build all examples and print a firmware size table");
    benchmark.dependOn(&bench_cmd.step);
}
