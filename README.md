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

- Zig `0.15.x` (verified with `0.15.2`)
- `../ch32fun/minichlink/minichlink`
- Linux/macOS shell environment (`sh`)
- Optional: `llvm-objdump` / `llvm-nm` (falls back to `riscv-none-elf-*`)

## Setup

1. Build `minichlink` from the `ch32fun` side:

```sh
make -C ../ch32fun/minichlink
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

## Common Commands

```sh
# Build example
zig build -Dexample=oled

# Show firmware size
zig build -Dexample=oled size

# Flash firmware
zig build -Dexample=oled flash
```

## Output Files

Build outputs are generated under `zig-out/firmware/`:

- `<example>.elf`
- `<example>.bin`
- `<example>.hex`
- `<example>.lst`
- `<example>.map`

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
