# ch32fun_zig (CH32V003)

`ch32fun_zig` is a lightweight pure-Zig environment for CH32V003 MCUs, inspired by the `ch32fun` workflow.  
You can build and flash firmware using GPIO / SysTick / I2C / SSD1306 with plain `zig build`.

Japanese version: [README_ja.md](README_ja.md)

## Features

- Pure Zig implementation for CH32V003
- Switch examples with `zig build -Dexample=<name>`
- Flash with `zig build ... flash` via `minichlink`
- Includes SSD1306 (I2C) and button-input examples

## Requirements

- Zig `0.16.0` (verified with `0.16.0`)
- `../ch32fun/minichlink/minichlink` (required for `flash`)
- Linux/macOS shell environment (`sh`, `make`)
- Optional (for `disasm` / `mapfile` / `size` steps):
  - `llvm-objdump` / `llvm-nm` / `llvm-size`, or
  - `riscv-none-elf-objdump` / `riscv-none-elf-nm` / `riscv-none-elf-size`

## Installing Dependencies

### macOS (Homebrew)

```sh
# Zig 0.16
brew install zig            # if Homebrew has not yet promoted 0.16, use the
                            # tarball install below instead

# LLVM tools (optional, for disasm / mapfile / size)
brew install llvm
# add the brew llvm bin to PATH if not already
echo 'export PATH="$(brew --prefix llvm)/bin:$PATH"' >> ~/.zshrc

# libusb is required to build minichlink
brew install libusb pkg-config
```

### Linux (Debian / Ubuntu)

```sh
# Build essentials and libusb for minichlink
sudo apt update
sudo apt install -y build-essential git pkg-config libusb-1.0-0-dev

# LLVM tools (optional, for disasm / mapfile / size)
sudo apt install -y llvm
```

### Linux (Arch)

```sh
sudo pacman -S --needed base-devel git pkgconf libusb llvm
```

### Installing Zig 0.16 from the official tarball (Mac/Linux)

If your package manager does not yet provide `0.16.0`, download it directly
from [ziglang.org/download](https://ziglang.org/download/):

```sh
# macOS (Apple Silicon)
curl -LO https://ziglang.org/download/0.16.0/zig-macos-aarch64-0.16.0.tar.xz
tar -xJf zig-macos-aarch64-0.16.0.tar.xz
sudo mv zig-macos-aarch64-0.16.0 /usr/local/zig-0.16.0
sudo ln -sf /usr/local/zig-0.16.0/zig /usr/local/bin/zig

# Linux (x86_64)
curl -LO https://ziglang.org/download/0.16.0/zig-linux-x86_64-0.16.0.tar.xz
tar -xJf zig-linux-x86_64-0.16.0.tar.xz
sudo mv zig-linux-x86_64-0.16.0 /usr/local/zig-0.16.0
sudo ln -sf /usr/local/zig-0.16.0/zig /usr/local/bin/zig
```

Verify:

```sh
zig version   # should print 0.16.0
```

## Setup

1. Clone `ch32fun` next to this repository and build `minichlink`:

```sh
# directory layout the build expects
# .
# ├── ch32fun/
# └── ch32fun_zig/   <-- you are here

cd ..
git clone https://github.com/cnlohr/ch32fun.git
make -C ch32fun/minichlink
cd ch32fun_zig
```

2. Build an example:

```sh
zig build -Dexample=blinky
```

3. Flash to the board:

```sh
zig build -Dexample=blinky flash
```

## Included Examples

- `blinky`
  - LED toggle on `PD0`
- `gpio_input`
  - Button input controls LED (`PD3` button, `PD0` LED)
- `timer_irq`
  - Periodic LED toggle using SysTick tick counter (`PD0`)
- `oled`
  - Renders rotated text/images and basic shapes on SSD1306
  - Toggle animation speed with button on `PD1`
- `persistent_counter`
  - Stores a boot counter in the last FLASH page (64 B reserved by the linker)
  - Blinks the LED on `PD0` once per boot count, survives power cycles
- `uart_hello`
  - Sends "hello" once per second over USART1 (PD5, 115200 8N1) via `fun.log`
- `led_fade`
  - Breathing LED on `PD2` driven by TIM1_CH1 PWM
- `tone_song`
  - Plays a C major scale through a passive buzzer on `PD4` (TIM2_CH1)
- `adc_meter`
  - Reads ADC ch3 (`PD2`), prints raw + mV over UART
- `exti_button`
  - Toggles `PD0` from an EXTI falling-edge ISR on `PD1`; main loop only `wfi`
- `compile_time_morse`
  - Expands a string into Morse code at `comptime`; runtime only blinks the LED on `PD0`
- `state_machine_game`
  - `tagged union` + exhaustive `switch` mini-game on the SSD1306 (button on `PD1`)
- `packed_settings`
  - Persists a `packed struct(u32)` of settings via `@bitCast` + Flash `Slot(T)`
- `comptime_lookup`
  - `comptime` sine table baked into `.rodata`, drives a PWM breathing LED on `PD2`
- `spi_loopback`
  - SPI1 master full-duplex check; tie `MOSI` (`PC6`) to `MISO` (`PC7`) and the LED on `PD0` confirms the echo
- `uart_dma`
  - Sends a message over USART1 via DMA1 ch4 while the CPU keeps blinking `PD0`
- `ir_text`
  - Sends and receives short UTF-8 strings over a 38kHz IR LED link (`PD0` TX, `PD1` demodulated RX)

## OLED Example Wiring

- OLED `SDA` -> `PC1`
- OLED `SCL` -> `PC2`
- OLED `VCC` / `GND` -> power rails
- Button -> `PD1` (internal pull-up enabled, active-low)

Notes:
- I2C is configured as `1MHz` Fast mode.
- SSD1306 I2C address is assumed to be `0x3C`.

## SSD1306 Drawing Helpers

- `drawStrRot`, `drawCharRot`, and `drawImageRot` support `0/90/180/270` rotation.
- `measureText` and `measureTextRot` help with centered/right-aligned layout using the built-in 8x8 font.
- Text can be drawn with transparent background by passing `opaque_bg=false`.
- Basic primitives are available: `drawLine`, `drawRect`, `fillRect`, `drawCircle`, `fillCircle`, `drawRoundRect`, `fillRoundRect`, `drawHLine`, `drawVLine`.
- `drawBitmapMasked` draws 1bpp sprites with a same-format 1bpp transparency mask.
- The implementation still uses a single 1024-byte framebuffer and does not allocate an extra rotation buffer.

## IR Text Example Wiring

- IR LED anode -> resistor -> `PD0`, cathode -> `GND`
- Demodulated 38kHz IR receiver `OUT` -> `PD1`
- Status LED -> `PD2`
- Receiver `VCC` / `GND` -> power rails required by the receiver module

`fun.ir` uses the `IRText v1` frame format: a 38kHz carrier, NEC-like pulse-distance bits, `"IR"` magic, version byte, payload length, UTF-8 payload bytes, and Dallas/Maxim CRC-8.

## Common Commands

```sh
# Build example (produces .elf / .bin / .hex)
zig build -Dexample=oled

# Flash firmware
zig build -Dexample=oled flash

# Show firmware size (requires llvm-size or riscv-none-elf-size)
zig build -Dexample=oled size

# Generate disassembly listing (requires llvm-objdump or riscv-none-elf-objdump)
zig build -Dexample=oled disasm

# Generate symbol map (requires llvm-nm or riscv-none-elf-nm)
zig build -Dexample=oled mapfile

# Build every example and print a firmware size table
# (uses llvm-size / riscv-none-elf-size when available, otherwise raw .bin size)
zig build benchmark
```

## Using as a Dependency

The HAL is a reusable Zig package. Add it to a downstream project and build
your own CH32V003 firmware without copying the target/linker boilerplate:

```zig
// build.zig.zon
.dependencies = .{
    .ch32fun_zig = .{ .path = "../ch32fun_zig" }, // or .url + .hash
},
```

```zig
// build.zig
const ch32 = @import("ch32fun_zig");

pub fn build(b: *std.Build) void {
    const dep = b.dependency("ch32fun_zig", .{});
    const fw = ch32.addFirmware(b, dep, .{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .optimize = .ReleaseSmall,
    });
    b.installArtifact(fw);
}
```

`addFirmware` wires in the `ch32fun` HAL import and the CH32V003 linker script
automatically; your `src/main.zig` can `@import("ch32fun")` directly.
The package also exposes `ch32Target(b)` and `halModule(pkg)` for finer control.

## Output Files

The default `zig build` produces the following under `zig-out/firmware/`:

- `<example>.elf`
- `<example>.bin`
- `<example>.hex`

Optional artifacts (generated only when their step is run explicitly):

- `<example>.lst` — `zig build … disasm`
- `<example>.map` — `zig build … mapfile`

## Repository Layout

- `src/`
  - HAL, register definitions, startup/runtime code
- `examples/`
  - Buildable firmware examples
- `tools/flash.sh`
  - Flash helper script that calls `minichlink`

## Current Scope / Limitations

- CH32V003 only (for now)
- `flash` target assumes `../ch32fun/minichlink/minichlink` exists
