#!/usr/bin/env sh
# Build every example and print a firmware size table.
#
# Prefers `llvm-size` / `riscv-none-elf-size` for an accurate text/data/bss
# breakdown. When neither is available it falls back to the raw `.bin`
# file size (the number of bytes actually flashed), so the benchmark still
# works on a bare `zig` install.
#
# Usage:
#   sh tools/size-benchmark.sh [optimize-mode]
#
#   optimize-mode defaults to ReleaseSmall (the project default).
set -eu

OPTIMIZE="${1:-ReleaseSmall}"

# Keep this list in sync with the `examples` array in build.zig.
EXAMPLES="blinky gpio_input timer_irq oled persistent_counter uart_hello \
led_fade tone_song adc_meter exti_button compile_time_morse \
state_machine_game packed_settings comptime_lookup spi_loopback uart_dma"

# Pick a size tool if one exists.
SIZE_TOOL=""
if command -v llvm-size >/dev/null 2>&1; then
  SIZE_TOOL="llvm-size"
elif command -v riscv-none-elf-size >/dev/null 2>&1; then
  SIZE_TOOL="riscv-none-elf-size"
fi

# FLASH (.text + .rodata + .data) is what occupies CH32V003 flash; SRAM is
# (.data + .bss). The `size` tool reports text/data/bss; we derive flash/ram.
printf '%-20s %10s %10s %10s\n' "example" "flash(B)" "sram(B)" "bin(B)"
printf '%-20s %10s %10s %10s\n' "-------" "--------" "-------" "------"

total_flash=0
total_bin=0

for ex in $EXAMPLES; do
  # Build quietly; surface failures.
  if ! zig build "-Dexample=$ex" "-Doptimize=$OPTIMIZE" >/dev/null 2>&1; then
    printf '%-20s %10s %10s %10s\n' "$ex" "BUILD-FAIL" "-" "-"
    continue
  fi

  elf="zig-out/firmware/${ex}.elf"
  bin="zig-out/firmware/${ex}.bin"

  bin_size="-"
  if [ -f "$bin" ]; then
    bin_size=$(wc -c < "$bin" | tr -d ' ')
  fi

  flash="-"
  sram="-"
  if [ -n "$SIZE_TOOL" ] && [ -f "$elf" ]; then
    # `size` default (Berkeley) format: "  text    data     bss     dec ..."
    line=$("$SIZE_TOOL" "$elf" 2>/dev/null | awk 'NR==2 {print $1, $2, $3}')
    set -- $line
    text="${1:-0}"
    data="${2:-0}"
    bss="${3:-0}"
    flash=$((text + data))
    sram=$((data + bss))
  fi

  printf '%-20s %10s %10s %10s\n' "$ex" "$flash" "$sram" "$bin_size"

  case "$bin_size" in
    ''|*[!0-9]*) ;;
    *) total_bin=$((total_bin + bin_size)) ;;
  esac
  case "$flash" in
    ''|*[!0-9]*) ;;
    *) total_flash=$((total_flash + flash)) ;;
  esac
done

printf '%-20s %10s %10s %10s\n' "-------" "--------" "-------" "------"
printf '%-20s %10s %10s %10s\n' "TOTAL" "$total_flash" "-" "$total_bin"

if [ -z "$SIZE_TOOL" ]; then
  echo
  echo "note: llvm-size / riscv-none-elf-size not found — flash/sram columns" >&2
  echo "      are blank; only raw .bin size is reported." >&2
fi
