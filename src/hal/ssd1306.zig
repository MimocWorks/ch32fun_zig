const i2c = @import("i2c.zig");
const font = @import("font8x8.zig");

pub const width: u8 = 128;
pub const height: u8 = 64;
const width_us: usize = width;
const height_us: usize = height;
const packet_size: usize = 32;
const i2c_addr: u7 = 0x3c;

pub const Error = i2c.Error;

pub const DrawMode = enum {
    normal,
    invert,
    and_mode,
    or_mode,
    or_invert,
    and_invert,
};

pub const FontSize = enum(u8) {
    x1 = 1,
    x2 = 2,
    x4 = 4,
    x8 = 8,
};

pub const Rotation = enum {
    deg0,
    deg90,
    deg180,
    deg270,
};

pub const Orientation = enum {
    landscape,
    portrait,
    landscape_flip,
    portrait_flip,
};

pub const TextExtent = struct {
    w: i16,
    h: i16,
};

pub var buffer: [width_us * height_us / 8]u8 = [_]u8{0} ** (width_us * height_us / 8);
var current_orientation: Orientation = .landscape;

const init_commands = [_]u8{
    0xAE,
    0xD5,
    0x80,
    0xA8,
    0x3F,
    0xD3,
    0x00,
    0x40,
    0x8D,
    0x14,
    0x20,
    0x00,
    0xA1,
    0xC8,
    0xDA,
    0x12,
    0x81,
    0xCF,
    0xD9,
    0xF1,
    0xDB,
    0x40,
    0xA4,
    0xA6,
    0xAF,
};

fn cmd(command: u8) Error!void {
    var pkt = [_]u8{ 0x00, command };
    try i2c.writeBlocking7bit(i2c_addr, pkt[0..]);
}

fn data(chunk: []const u8) Error!void {
    var pkt: [packet_size + 1]u8 = undefined;
    pkt[0] = 0x40;
    @memcpy(pkt[1 .. 1 + chunk.len], chunk);
    try i2c.writeBlocking7bit(i2c_addr, pkt[0 .. 1 + chunk.len]);
}

fn mapPoint(x: i16, y: i16) ?struct { x: i16, y: i16 } {
    if (x < 0 or y < 0) return null;
    if (x >= logicalWidth() or y >= logicalHeight()) return null;

    return switch (current_orientation) {
        .landscape => .{ .x = x, .y = y },
        .landscape_flip => .{ .x = @as(i16, width) - 1 - x, .y = @as(i16, height) - 1 - y },
        .portrait => .{ .x = @as(i16, width) - 1 - y, .y = x },
        .portrait_flip => .{ .x = y, .y = @as(i16, height) - 1 - x },
    };
}

fn blendPhysicalPixel(x: i16, y: i16, src_on: bool, mode: DrawMode) void {
    const xu: usize = @intCast(x);
    const yu: usize = @intCast(y);
    const addr = xu + @as(usize, width) * (yu / 8);
    const mask: u8 = @as(u8, 1) << @as(u3, @intCast(yu & 7));
    const dst_on = (buffer[addr] & mask) != 0;

    const out_on = switch (mode) {
        .normal => src_on,
        .invert => !src_on,
        .and_mode => dst_on and src_on,
        .or_mode => dst_on or src_on,
        .or_invert => dst_on or !src_on,
        .and_invert => dst_on and !src_on,
    };

    if (out_on) {
        buffer[addr] |= mask;
    } else {
        buffer[addr] &= ~mask;
    }
}

fn blendPixel(x: i16, y: i16, src_on: bool, mode: DrawMode) void {
    const p = mapPoint(x, y) orelse return;
    blendPhysicalPixel(p.x, p.y, src_on, mode);
}

fn rotatePoint(sx: i16, sy: i16, w: i16, h: i16, rotation: Rotation) struct { x: i16, y: i16 } {
    return switch (rotation) {
        .deg0 => .{ .x = sx, .y = sy },
        .deg90 => .{ .x = h - 1 - sy, .y = sx },
        .deg180 => .{ .x = w - 1 - sx, .y = h - 1 - sy },
        .deg270 => .{ .x = sy, .y = w - 1 - sx },
    };
}

fn rotatedDimensions(w: i16, h: i16, rotation: Rotation) struct { w: i16, h: i16 } {
    return switch (rotation) {
        .deg0, .deg180 => .{ .w = w, .h = h },
        .deg90, .deg270 => .{ .w = h, .h = w },
    };
}

fn imagePixel(input: []const u8, w: u8, x: u8, y: u8) bool {
    const bytes_per_row = (@as(usize, w) + 7) / 8;
    const addr = @as(usize, y) * bytes_per_row + (@as(usize, x) / 8);
    const bit_index: u3 = @intCast(7 - (x & 7));
    return (input[addr] & (@as(u8, 1) << bit_index)) != 0;
}

fn glyphPixel(chr: u8, x: u8, y: u8) bool {
    const glyph_base = (@as(usize, chr) << 3);
    return (font.fontdata[glyph_base + y] & (@as(u8, 0x80) >> @as(u3, @intCast(x)))) != 0;
}

fn clampRadius(w: i16, h: i16, radius: i16) i16 {
    if (radius <= 0 or w <= 0 or h <= 0) return 0;
    const max_x = @divTrunc(w - 1, 2);
    const max_y = @divTrunc(h - 1, 2);
    return @min(radius, @min(max_x, max_y));
}

fn min3(a: i16, b: i16, c: i16) i16 {
    return @min(a, @min(b, c));
}

fn max3(a: i16, b: i16, c: i16) i16 {
    return @max(a, @max(b, c));
}

fn edgeSign(px: i16, py: i16, ax: i16, ay: i16, bx: i16, by: i16) i32 {
    return (@as(i32, px) - @as(i32, bx)) * (@as(i32, ay) - @as(i32, by)) -
        (@as(i32, ax) - @as(i32, bx)) * (@as(i32, py) - @as(i32, by));
}

fn triangleContains(px: i16, py: i16, x0: i16, y0: i16, x1: i16, y1: i16, x2: i16, y2: i16) bool {
    const d1 = edgeSign(px, py, x0, y0, x1, y1);
    const d2 = edgeSign(px, py, x1, y1, x2, y2);
    const d3 = edgeSign(px, py, x2, y2, x0, y0);

    const has_neg = d1 < 0 or d2 < 0 or d3 < 0;
    const has_pos = d1 > 0 or d2 > 0 or d3 > 0;
    return !(has_neg and has_pos);
}

pub fn initI2c() !void {
    i2c.initI2c1FastMode();
}

pub fn initPanel() !void {
    try initPanelWithOrientation(.landscape);
}

pub fn initPanelWithOrientation(panel_orientation: Orientation) !void {
    setOrientation(panel_orientation);
    for (init_commands) |c| {
        try cmd(c);
    }
    setbuf(false);
    try refresh();
}

pub fn setOrientation(panel_orientation: Orientation) void {
    current_orientation = panel_orientation;
}

pub fn orientation() Orientation {
    return current_orientation;
}

pub fn logicalWidth() u8 {
    return switch (current_orientation) {
        .landscape, .landscape_flip => width,
        .portrait, .portrait_flip => height,
    };
}

pub fn logicalHeight() u8 {
    return switch (current_orientation) {
        .landscape, .landscape_flip => height,
        .portrait, .portrait_flip => width,
    };
}

pub fn setbuf(color: bool) void {
    @memset(&buffer, if (color) 0xFF else 0x00);
}

pub fn refresh() !void {
    try cmd(0x21);
    try cmd(0);
    try cmd(width - 1);

    try cmd(0x22);
    try cmd(0);
    try cmd(7);

    var i: usize = 0;
    while (i < buffer.len) : (i += packet_size) {
        const end = @min(i + packet_size, buffer.len);
        try data(buffer[i..end]);
    }
}

pub fn drawPixel(x: i16, y: i16, color: bool) void {
    blendPixel(x, y, color, .normal);
}

pub fn measureText(text: []const u8, font_size: FontSize) TextExtent {
    return measureTextRot(text, font_size, .deg0);
}

pub fn measureTextRot(text: []const u8, font_size: FontSize, rotation: Rotation) TextExtent {
    if (text.len == 0) return .{ .w = 0, .h = 0 };

    const scale: i16 = @intCast(@intFromEnum(font_size));
    const dims = rotatedDimensions(@as(i16, @intCast(text.len)) * 8 * scale, 8 * scale, rotation);
    return .{ .w = dims.w, .h = dims.h };
}

pub fn drawImage(x: i16, y: i16, input: []const u8, w: u8, h: u8, mode: DrawMode) void {
    drawImageRot(x, y, input, w, h, mode, .deg0);
}

pub fn drawImageRot(x: i16, y: i16, input: []const u8, w: u8, h: u8, mode: DrawMode, rotation: Rotation) void {
    if (w == 0 or h == 0) return;

    var sy: u8 = 0;
    while (sy < h) : (sy += 1) {
        var sx: u8 = 0;
        while (sx < w) : (sx += 1) {
            const dest = rotatePoint(@as(i16, sx), @as(i16, sy), @as(i16, w), @as(i16, h), rotation);
            blendPixel(x + dest.x, y + dest.y, imagePixel(input, w, sx, sy), mode);
        }
    }
}

pub fn drawBitmapMasked(x: i16, y: i16, input: []const u8, mask: []const u8, w: u8, h: u8, mode: DrawMode, rotation: Rotation) void {
    if (w == 0 or h == 0) return;

    var sy: u8 = 0;
    while (sy < h) : (sy += 1) {
        var sx: u8 = 0;
        while (sx < w) : (sx += 1) {
            if (!imagePixel(mask, w, sx, sy)) continue;
            const dest = rotatePoint(@as(i16, sx), @as(i16, sy), @as(i16, w), @as(i16, h), rotation);
            blendPixel(x + dest.x, y + dest.y, imagePixel(input, w, sx, sy), mode);
        }
    }
}

pub fn drawCharSz(x: i16, y: i16, chr: u8, color: bool, font_size: FontSize) void {
    drawCharRot(x, y, chr, color, font_size, .deg0, true);
}

pub fn drawCharRot(x: i16, y: i16, chr: u8, color: bool, font_size: FontSize, rotation: Rotation, opaque_bg: bool) void {
    const scale: u8 = @intFromEnum(font_size);
    const glyph_w: i16 = 8 * @as(i16, scale);
    const glyph_h: i16 = 8 * @as(i16, scale);

    var row: u8 = 0;
    while (row < 8) : (row += 1) {
        var col: u8 = 0;
        while (col < 8) : (col += 1) {
            const src_on = glyphPixel(chr, col, row);
            if (!src_on and !opaque_bg) continue;

            const pixel_on = if (src_on) color else !color;

            var sy: u8 = 0;
            while (sy < scale) : (sy += 1) {
                var sx: u8 = 0;
                while (sx < scale) : (sx += 1) {
                    const src_x = @as(i16, col) * @as(i16, scale) + @as(i16, sx);
                    const src_y = @as(i16, row) * @as(i16, scale) + @as(i16, sy);
                    const dest = rotatePoint(src_x, src_y, glyph_w, glyph_h, rotation);
                    drawPixel(x + dest.x, y + dest.y, pixel_on);
                }
            }
        }
    }
}

pub fn drawStrSz(x_start: i16, y: i16, text: []const u8, color: bool, font_size: FontSize) void {
    drawStrRot(x_start, y, text, color, font_size, .deg0, true);
}

pub fn drawStrRot(x_start: i16, y_start: i16, text: []const u8, color: bool, font_size: FontSize, rotation: Rotation, opaque_bg: bool) void {
    const step: i16 = @as(i16, 8) * @as(i16, @intCast(@intFromEnum(font_size)));
    const text_len: i16 = @intCast(text.len);
    const Point = struct { x: i16, y: i16 };
    const bounds = rotatedDimensions(step, step, rotation);

    for (text, 0..) |c, idx| {
        const i: i16 = @intCast(idx);
        const pos: Point = switch (rotation) {
            .deg0 => .{ .x = x_start + i * step, .y = y_start },
            .deg90 => .{ .x = x_start, .y = y_start + i * step },
            .deg180 => .{ .x = x_start + (text_len - 1 - i) * step, .y = y_start },
            .deg270 => .{ .x = x_start, .y = y_start + (text_len - 1 - i) * step },
        };
        if (pos.x >= logicalWidth() or pos.y >= logicalHeight()) break;
        if (pos.x <= -bounds.w or pos.y <= -bounds.h) continue;
        drawCharRot(pos.x, pos.y, c, color, font_size, rotation, opaque_bg);
    }
}

pub fn drawHLine(x: i16, y: i16, len: i16, color: bool) void {
    if (len <= 0) return;
    var i: i16 = 0;
    while (i < len) : (i += 1) {
        drawPixel(x + i, y, color);
    }
}

pub fn drawVLine(x: i16, y: i16, len: i16, color: bool) void {
    if (len <= 0) return;
    var i: i16 = 0;
    while (i < len) : (i += 1) {
        drawPixel(x, y + i, color);
    }
}

pub fn drawLine(x0_in: i16, y0_in: i16, x1_in: i16, y1_in: i16, color: bool) void {
    var x0 = x0_in;
    var y0 = y0_in;
    const x1 = x1_in;
    const y1 = y1_in;

    const dx: i16 = @intCast(@abs(x1 - x0));
    const sx: i16 = if (x0 < x1) 1 else -1;
    const dy: i16 = -@as(i16, @intCast(@abs(y1 - y0)));
    const sy: i16 = if (y0 < y1) 1 else -1;
    var err: i16 = dx + dy;

    while (true) {
        drawPixel(x0, y0, color);
        if (x0 == x1 and y0 == y1) break;

        const e2 = err * 2;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

pub fn drawLineThick(x0_in: i16, y0_in: i16, x1_in: i16, y1_in: i16, thickness: i16, color: bool) void {
    if (thickness <= 1) {
        drawLine(x0_in, y0_in, x1_in, y1_in, color);
        return;
    }

    var x0 = x0_in;
    var y0 = y0_in;
    const x1 = x1_in;
    const y1 = y1_in;
    const brush = thickness;
    const offset = @divTrunc(brush, 2);

    const dx: i16 = @intCast(@abs(x1 - x0));
    const sx: i16 = if (x0 < x1) 1 else -1;
    const dy: i16 = -@as(i16, @intCast(@abs(y1 - y0)));
    const sy: i16 = if (y0 < y1) 1 else -1;
    var err: i16 = dx + dy;

    while (true) {
        fillRect(x0 - offset, y0 - offset, brush, brush, color);
        if (x0 == x1 and y0 == y1) break;

        const e2 = err * 2;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

pub fn drawRect(x: i16, y: i16, w: i16, h: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    drawHLine(x, y, w, color);
    if (h > 1) drawHLine(x, y + h - 1, w, color);
    if (h > 2) {
        drawVLine(x, y + 1, h - 2, color);
        if (w > 1) drawVLine(x + w - 1, y + 1, h - 2, color);
    }
}

pub fn drawRectThick(x: i16, y: i16, w: i16, h: i16, thickness: i16, color: bool) void {
    if (w <= 0 or h <= 0 or thickness <= 0) return;

    const t = @min(thickness, @divTrunc(@min(w, h) + 1, 2));
    var i: i16 = 0;
    while (i < t) : (i += 1) {
        drawRect(x + i, y + i, w - i * 2, h - i * 2, color);
    }
}

pub fn fillRect(x: i16, y: i16, w: i16, h: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    var row: i16 = 0;
    while (row < h) : (row += 1) {
        drawHLine(x, y + row, w, color);
    }
}

pub fn drawFrame(x: i16, y: i16, w: i16, h: i16, thickness: i16, border_color: bool, fill_color: bool) void {
    if (w <= 0 or h <= 0) return;
    fillRect(x, y, w, h, fill_color);
    drawRectThick(x, y, w, h, thickness, border_color);
}

pub fn drawTriangle(x0: i16, y0: i16, x1: i16, y1: i16, x2: i16, y2: i16, color: bool) void {
    drawLine(x0, y0, x1, y1, color);
    drawLine(x1, y1, x2, y2, color);
    drawLine(x2, y2, x0, y0, color);
}

pub fn fillTriangle(x0: i16, y0: i16, x1: i16, y1: i16, x2: i16, y2: i16, color: bool) void {
    const min_x = @max(min3(x0, x1, x2), 0);
    const max_x = @min(max3(x0, x1, x2), @as(i16, logicalWidth()) - 1);
    var y_pos = @max(min3(y0, y1, y2), 0);
    const max_y = @min(max3(y0, y1, y2), @as(i16, logicalHeight()) - 1);

    if (min_x > max_x or y_pos > max_y) return;

    while (y_pos <= max_y) : (y_pos += 1) {
        var span_started = false;
        var span_start: i16 = min_x;
        var x_pos = min_x;
        while (x_pos <= max_x) : (x_pos += 1) {
            const inside = triangleContains(x_pos, y_pos, x0, y0, x1, y1, x2, y2);
            if (inside and !span_started) {
                span_started = true;
                span_start = x_pos;
            } else if (!inside and span_started) {
                drawHLine(span_start, y_pos, x_pos - span_start, color);
                span_started = false;
            }
        }
        if (span_started) {
            drawHLine(span_start, y_pos, max_x - span_start + 1, color);
        }
    }
}

pub fn drawCircle(x0: i16, y0: i16, radius: i16, color: bool) void {
    if (radius < 0) return;

    var x = radius;
    var y: i16 = 0;
    var err: i16 = 1 - radius;

    while (x >= y) {
        drawPixel(x0 + x, y0 + y, color);
        drawPixel(x0 + y, y0 + x, color);
        drawPixel(x0 - y, y0 + x, color);
        drawPixel(x0 - x, y0 + y, color);
        drawPixel(x0 - x, y0 - y, color);
        drawPixel(x0 - y, y0 - x, color);
        drawPixel(x0 + y, y0 - x, color);
        drawPixel(x0 + x, y0 - y, color);

        y += 1;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            x -= 1;
            err += 2 * (y - x) + 1;
        }
    }
}

pub fn drawCircleThick(x0: i16, y0: i16, radius: i16, thickness: i16, color: bool) void {
    if (radius < 0 or thickness <= 0) return;

    var i: i16 = 0;
    while (i < thickness and radius - i >= 0) : (i += 1) {
        drawCircle(x0, y0, radius - i, color);
    }
}

pub fn fillCircle(x0: i16, y0: i16, radius: i16, color: bool) void {
    if (radius < 0) return;
    if (radius == 0) {
        drawPixel(x0, y0, color);
        return;
    }

    var x = radius;
    var y: i16 = 0;
    var err: i16 = 1 - radius;

    while (x >= y) {
        drawHLine(x0 - x, y0 + y, 2 * x + 1, color);
        drawHLine(x0 - x, y0 - y, 2 * x + 1, color);
        drawHLine(x0 - y, y0 + x, 2 * y + 1, color);
        drawHLine(x0 - y, y0 - x, 2 * y + 1, color);

        y += 1;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            x -= 1;
            err += 2 * (y - x) + 1;
        }
    }
}

pub fn drawEllipse(x0: i16, y0: i16, rx: i16, ry: i16, color: bool) void {
    if (rx < 0 or ry < 0) return;
    if (rx == 0) {
        drawVLine(x0, y0 - ry, ry * 2 + 1, color);
        return;
    }
    if (ry == 0) {
        drawHLine(x0 - rx, y0, rx * 2 + 1, color);
        return;
    }

    var y: i16 = -ry;
    while (y <= ry) : (y += 1) {
        var x: i16 = -rx;
        while (x <= rx) : (x += 1) {
            const lhs = @as(i32, x) * @as(i32, x) * @as(i32, ry) * @as(i32, ry) +
                @as(i32, y) * @as(i32, y) * @as(i32, rx) * @as(i32, rx);
            const rhs = @as(i32, rx) * @as(i32, rx) * @as(i32, ry) * @as(i32, ry);
            const border = @abs(lhs - rhs) <= @as(i32, @max(rx * rx, ry * ry));
            if (border) drawPixel(x0 + x, y0 + y, color);
        }
    }
}

pub fn fillEllipse(x0: i16, y0: i16, rx: i16, ry: i16, color: bool) void {
    if (rx < 0 or ry < 0) return;
    if (rx == 0) {
        drawVLine(x0, y0 - ry, ry * 2 + 1, color);
        return;
    }
    if (ry == 0) {
        drawHLine(x0 - rx, y0, rx * 2 + 1, color);
        return;
    }

    var y: i16 = -ry;
    while (y <= ry) : (y += 1) {
        var span_start: ?i16 = null;
        var x: i16 = -rx;
        while (x <= rx) : (x += 1) {
            const inside = @as(i32, x) * @as(i32, x) * @as(i32, ry) * @as(i32, ry) +
                @as(i32, y) * @as(i32, y) * @as(i32, rx) * @as(i32, rx) <=
                @as(i32, rx) * @as(i32, rx) * @as(i32, ry) * @as(i32, ry);
            if (inside and span_start == null) {
                span_start = x;
            } else if (!inside and span_start != null) {
                const start = span_start.?;
                drawHLine(x0 + start, y0 + y, x - start, color);
                span_start = null;
            }
        }
        if (span_start) |start| {
            drawHLine(x0 + start, y0 + y, rx - start + 1, color);
        }
    }
}

pub fn drawRoundRect(x: i16, y: i16, w: i16, h: i16, radius_in: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    const radius = clampRadius(w, h, radius_in);
    if (radius == 0) {
        drawRect(x, y, w, h, color);
        return;
    }

    drawHLine(x + radius, y, w - 2 * radius, color);
    drawHLine(x + radius, y + h - 1, w - 2 * radius, color);
    drawVLine(x, y + radius, h - 2 * radius, color);
    drawVLine(x + w - 1, y + radius, h - 2 * radius, color);

    var dx = radius;
    var dy: i16 = 0;
    var err: i16 = 1 - radius;

    while (dx >= dy) {
        drawPixel(x + radius - dx, y + radius - dy, color);
        drawPixel(x + radius - dy, y + radius - dx, color);
        drawPixel(x + w - radius - 1 + dx, y + radius - dy, color);
        drawPixel(x + w - radius - 1 + dy, y + radius - dx, color);
        drawPixel(x + radius - dx, y + h - radius - 1 + dy, color);
        drawPixel(x + radius - dy, y + h - radius - 1 + dx, color);
        drawPixel(x + w - radius - 1 + dx, y + h - radius - 1 + dy, color);
        drawPixel(x + w - radius - 1 + dy, y + h - radius - 1 + dx, color);

        dy += 1;
        if (err < 0) {
            err += 2 * dy + 1;
        } else {
            dx -= 1;
            err += 2 * (dy - dx) + 1;
        }
    }
}

pub fn drawRoundRectThick(x: i16, y: i16, w: i16, h: i16, radius_in: i16, thickness: i16, color: bool) void {
    if (w <= 0 or h <= 0 or thickness <= 0) return;

    const t = @min(thickness, @divTrunc(@min(w, h) + 1, 2));
    var i: i16 = 0;
    while (i < t) : (i += 1) {
        drawRoundRect(x + i, y + i, w - i * 2, h - i * 2, radius_in - i, color);
    }
}

pub fn fillRoundRect(x: i16, y: i16, w: i16, h: i16, radius_in: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    const radius = clampRadius(w, h, radius_in);
    if (radius == 0) {
        fillRect(x, y, w, h, color);
        return;
    }

    fillRect(x + radius, y, w - 2 * radius, h, color);

    var dx = radius;
    var dy: i16 = 0;
    var err: i16 = 1 - radius;

    while (dx >= dy) {
        drawHLine(x + radius - dx, y + radius - dy, w - 2 * radius + 2 * dx, color);
        drawHLine(x + radius - dx, y + h - radius - 1 + dy, w - 2 * radius + 2 * dx, color);
        drawHLine(x + radius - dy, y + radius - dx, w - 2 * radius + 2 * dy, color);
        drawHLine(x + radius - dy, y + h - radius - 1 + dx, w - 2 * radius + 2 * dy, color);

        dy += 1;
        if (err < 0) {
            err += 2 * dy + 1;
        } else {
            dx -= 1;
            err += 2 * (dy - dx) + 1;
        }
    }
}

pub fn drawRoundFrame(x: i16, y: i16, w: i16, h: i16, radius: i16, thickness: i16, border_color: bool, fill_color: bool) void {
    if (w <= 0 or h <= 0) return;
    fillRoundRect(x, y, w, h, radius, fill_color);
    drawRoundRectThick(x, y, w, h, radius, thickness, border_color);
}

pub fn drawProgressBar(x: i16, y: i16, w: i16, h: i16, value: u16, max_value: u16, border_color: bool, fill_color: bool) void {
    if (w <= 0 or h <= 0) return;

    drawRect(x, y, w, h, border_color);
    if (w <= 2 or h <= 2 or max_value == 0) return;

    const inner_w = w - 2;
    const inner_w_u: u32 = @intCast(inner_w);
    const fill_w: i16 = @intCast(inner_w_u * @as(u32, @min(value, max_value)) / @as(u32, max_value));
    if (fill_w > 0) {
        fillRect(x + 1, y + 1, fill_w, h - 2, fill_color);
    }
}
