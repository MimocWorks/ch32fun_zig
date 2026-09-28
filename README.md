# ch32fun_zig (CH32V003)

`ch32fun_zig` is a lightweight pure-Zig environment for CH32V003 MCUs, inspired by the `ch32fun` workflow.  
You can build and flash firmware using GPIO / SysTick / I2C / SSD1306 with plain `zig build`.

Japanese version: [README_ja.md](README_ja.md)

## Features

- Pure Zig implementation for CH32V003
- Switch examples with `zig build -Dexample=<name>`
- Flash with `zig build ... flash` via the Zig WCH-LinkE writer
- Includes SSD1306 (I2C) and button-input examples

## Requirements

- Zig `0.16.0` (verified with `0.16.0`)
- WCH-LinkE in RISC-V mode and libusb 1.0 at flash time
- Linux/macOS shell environment (`sh`)
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

# libusb is loaded by the WCH-LinkE writer at runtime
brew install libusb
```

### Linux (Debian / Ubuntu)

```sh
# libusb runtime for the WCH-LinkE writer
sudo apt update
sudo apt install -y libusb-1.0-0

# LLVM tools (optional, for disasm / mapfile / size)
sudo apt install -y llvm
```

### Linux (Arch)

```sh
sudo pacman -S --needed libusb llvm
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

1. Build an example:

```sh
zig build -Dexample=blinky
```

2. Flash to the board:

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
- `swio_log`
  - Emits formatted SWIO logs for display by `minichlink -T`
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
- `hc_sr04`
  - Measures distance with an HC-SR04 (`PD0` trigger, `PD1` echo) and reports millimetres over USART1
- `ir_text`
  - Sends and receives short UTF-8 strings over a 38kHz IR LED link (`PD0` TX, `PD1` demodulated RX)
- `register_blinky`
  - Blinks `PD0` by directly writing RCC / GPIOD / SysTick MMIO registers, without the GPIO/time HAL helpers

## SWIO print debugging

`fun.swio_log` is compatible with the C ch32fun DebugPrintf protocol and emits
formatted logs without consuming an extra UART pin. Debug builds enable it by
default. To fit comfortably in 16 KiB, an optimized diagnostic build is recommended.
The small-footprint formatter supports integer `{d}` and `{x}`, string `{s}`, and
type-dependent `{}` placeholders.

```zig
pub const ch32fun_swio_log_enabled = true;

fun.swio_log.init();
fun.swio_log.waitForTerminal(); // When early boot logs must be captured
fun.swio_log.info("value={d} flags=0x{x}", .{ value, flags });
fun.swio_log.warn("waiting", .{});
fun.swio_log.err("failed code={d}", .{code});
```

Build and flash, then start the terminal:

```sh
zig build -Dexample=swio_log -Doptimize=ReleaseSmall
zig build -Dexample=swio_log -Doptimize=ReleaseSmall flash
minichlink -T # only if you separately install a SWIO terminal
```

Without a root override, `swio_log.enabled` is compile-time false in `ReleaseSmall`,
`ReleaseFast`, and `ReleaseSafe`. Every logging function becomes a no-op, and
formatting code, strings, and DMDATA accesses are removed from the final image.
Set the root declaration to false to remove logs from a Debug build as well.

```zig
if (fun.swio_log.enabled) fun.swio_log.info("debug only", .{});
```

Logging is blocking. Do not call it from an ISR or timing-sensitive code such as
IR transmit/receive. `waitForTerminal()` prevents firmware progress until
`minichlink -T` starts. PD1 is occupied by SWIO while the terminal is attached.

## HC-SR04 Example Wiring

- HC-SR04 `TRIG` -> `PD0`
- HC-SR04 `ECHO` -> voltage divider / level shifter -> `PD1`
- HC-SR04 `VCC` -> `5V`
- HC-SR04 `GND` -> `GND`
- USB-serial RX -> `PD5` (`115200` baud, 8N1)

The HC-SR04 ECHO output is 5V logic. Do not connect it directly to the
CH32V003; reduce it to 3.3V or below with a resistor divider or level shifter.

## OLED Example Wiring

- OLED `SDA` -> `PC1`
- OLED `SCL` -> `PC2`
- OLED `VCC` / `GND` -> power rails
- Button -> `PD1` (internal pull-up enabled, active-low)

Notes:
- I2C is configured as `1MHz` Fast mode.
- SSD1306 I2C address is detected automatically (`0x3C`, then `0x3D`).
- SSD1306 panel geometry defaults to `128x64`. For a `128x32` panel, declare `pub const ch32fun_ssd1306_panel_size = .@"128x32";` in the application root. Initialization, coordinates, full-buffer size, and transferred page count switch together.

## SSD1306 Drawing Helpers

- `initPanelWithOrientation(.portrait)` / `.landscape` / `.landscape_flip` / `.portrait_flip` selects the logical screen orientation at initialization.
- `logicalWidth()` / `logicalHeight()` return the active logical coordinate size (`64x128` in portrait orientations).
- `drawStrRot`, `drawCharRot`, and `drawImageRot` support `0/90/180/270` rotation.
- `measureText` and `measureTextRot` help with centered/right-aligned layout using the built-in 8x8 font.
- The full 256-glyph font remains the default. Size-constrained firmware can opt into the 728-byte ASCII `0x20`-`0x7A` subset by declaring `pub const ch32fun_ssd1306_basic_ascii_font = true;` in its root source file; characters outside that range render blank.
- Text can be drawn with transparent background by passing `opaque_bg=false`.
- Basic primitives are available: `drawLine`, `drawRect`, `fillRect`, `drawCircle`, `fillCircle`, `drawRoundRect`, `fillRoundRect`, `drawHLine`, `drawVLine`.
- Enhanced helpers include `drawLineThick`, `drawRectThick`, `drawCircleThick`, `drawRoundRectThick`, `drawFrame`, `drawRoundFrame`, `drawTriangle`, `fillTriangle`, `drawEllipse`, `fillEllipse`, and `drawProgressBar`.
- `drawBitmapMasked` draws 1bpp sprites with a same-format 1bpp transparency mask.
- Full-buffer mode remains the default and uses 1,024 bytes for 128x64 or 512 bytes for 128x32. Declare `pub const ch32fun_ssd1306_buffer_mode = .page;` to select a 128-byte page buffer; render an immutable scene between `firstPage()` and repeated `nextPage()` calls. See [SSD1306 page rendering](docs/ssd1306-page-rendering.md).

## Button Input Helper

`fun.input.Button` supports buttons on arbitrary GPIO pins:

```zig
const a = fun.input.Button.init(.{
    .pin = fun.gpio.pin(.D, 1),
    .pull = .up,
    .active = .low,
});
const b = fun.input.button(.{
    .pin = fun.gpio.pin(.D, 3),
    .pull = .down,
    .active = .high,
});

if (a.isPressed() or b.isPressed()) {
    // ...
}
```

The older `initButtonPd1Pullup()` / `isButtonPressed()` helpers remain as
PD1 active-low shortcuts for existing examples.

## IR Text Example Wiring

- IR LED anode -> resistor -> `PD0`, cathode -> `GND`
- Demodulated 38kHz IR receiver `OUT` -> `PD1`
- Status LED -> `PD2`
- Receiver `VCC` / `GND` -> power rails required by the receiver module

`fun.ir` uses the `IRText v1` frame format: a 38kHz carrier, NEC-like pulse-distance bits, `"IR"` magic, version byte, payload length, UTF-8 payload bytes, and Dallas/Maxim CRC-8.

For a low-jitter carrier on CH32V003J4M6, set
`Tx.carrier_mode = .tim1_ch4_pc4` and connect the driver to `PC4`.
`sendPacket32` / `recvPacket32` provide a compact fixed-size NEC-like frame.
`sendFrame8` / `recvFrame8` provide an eight-byte form without application-side
64-bit arithmetic.

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

## Project Scaffolding

Install the `chzig` helper command from this checkout:

```sh
sh tools/install-chzig.sh
```

Then create a new project that depends on this package and has every HAL module
available through `@import("ch32fun")`:

```sh
chzig init my_firmware
cd my_firmware
zig build
chzig flash
```

By default the installer writes `chzig` to `$HOME/.local/bin`. Use
`sh tools/install-chzig.sh --prefix /path/to/prefix` to choose another prefix.
The installer builds and bundles this repository's Zig WCH-LinkE writer into the install
prefix, so `chzig flash` can build and write `zig-out/firmware/firmware.bin`
without depending on the original checkout layout.
After building, `chzig flash` prints FLASH and RAM usage as percentage bars
before flashing. FLASH is measured against the 16,320-byte
application region; the final 64-byte page remains reserved for user data.
Each written 64-byte page is read back for verification.

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
  - Flash helper script that calls the Zig writer
- `tools/wchlinke.zig`
  - WCH-LinkE flash writer

## Current Scope / Limitations

- CH32V003 only (for now)
- Writer supports WCH-LinkE in RISC-V mode and CH32V003 only
- libusb 1.0 is required at runtime for USB transport
