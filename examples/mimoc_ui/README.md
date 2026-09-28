# CH32V003 + SSD1306 integration

Build from this directory after cloning `mimoc-ui` and `ch32fun_zig` as siblings:

```sh
zig build
```

The firmware uses ch32fun_zig's 128-byte SSD1306 page buffer directly. PD1's pull-up button advances focus among CHAT, CQ, and EHAGAKI. The selection marker animates from a single fixed-capacity presentation track. The Core neither imports ch32fun_zig nor owns the display driver.

Capacity variants can be built with `zig build -Dmax_nodes=8 -Dmax_animations=1` (also tested with 12/1, 16/1, and 16/4). The 8/1 linked image occupies 12,068 bytes of Flash and 516 bytes of static RAM, including the HAL page buffer. All measured static sizes are recorded in `mimoc-ui/docs/milestone-7-progress.md`.

This is a buildable integration sample. Board flashing, physical input/display checks, stack measurement, and frame timing require connected hardware.
