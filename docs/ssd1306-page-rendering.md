# SSD1306 page rendering

`ch32fun_zig` supports two compile-time drawing-storage modes. The default
`.full` mode stores the complete image in 1,024 bytes for 128x64 or 512 bytes for
128x32 and preserves the legacy `setbuf()` / drawing / `refresh()` flow. `.page`
stores one 128x8 GDDRAM page in 128 bytes, recovering 896 or 384 bytes of static
RAM respectively.

Select page mode in the application root:

```zig
pub const ch32fun_ssd1306_buffer_mode = .page;
```

Select a 128x32 panel (128x64 remains the default):

```zig
pub const ch32fun_ssd1306_panel_size = .@"128x32";
```

Render a complete immutable picture in a picture loop:

```zig
const snapshot = .{ .score = score, .text = storage[0..text_len] };
fun.ssd1306.firstPage();
while (true) {
    drawScreen(snapshot);
    if (!(try fun.ssd1306.nextPage())) break;
}
```

In page mode `drawScreen` runs eight times for 128x64 or four times for 128x32.
It must not consume input, advance a clock, mutate game/protocol state, or create
another large image copy. Snapshot
small scalars by value and reference existing fixed storage with bounded slices.
The renderer maps logical orientation first, then rejects pixels outside the
current physical page before indexing the 128-byte array. Consequently text,
vertical lines, and rectangles may cross page boundaries without application
special cases.

`nextPage()` transfers four 32-byte I2C data packets through `writePage()`.
SSD1306/SSD1309 page and column ranges and the SH1106 two-column offset remain
inside the HAL. Address probing at `0x3c` then `0x3d` is unchanged. In full mode
the same picture-loop API draws once and refreshes the full image, so reusable
application drawing code does not need a mode branch. The unselected buffer size
is eliminated at comptime and consumes no static RAM in the final image.

Page mode keeps the I2C payload at the panel's full image size per display update
but recomputes the scene for each page and sends page-address commands per band. Prefer
it where RAM is scarce; prefer full mode where CPU time is more important. A
future dirty-page policy can be added above `writePage()`, but is intentionally
not part of the current state or RAM budget.

Run the hardware-independent clipping and page-boundary tests with:

```sh
zig test src/ssd1306_test.zig
```
