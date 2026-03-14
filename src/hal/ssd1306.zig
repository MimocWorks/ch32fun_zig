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

pub const TextExtent = struct {
    w: i16,
    h: i16,
};

pub var buffer: [width_us * height_us / 8]u8 = [_]u8{0} ** (width_us * height_us / 8);

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

fn blendPixel(x: i16, y: i16, src_on: bool, mode: DrawMode) void {
    if (x < 0 or y < 0) return;
    if (x >= width or y >= height) return;

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

pub fn initI2c() !void {
    i2c.initI2c1FastMode();
}

pub fn initPanel() !void {
    for (init_commands) |c| {
        try cmd(c);
    }
    setbuf(false);
    try refresh();
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
    if (x < 0 or y < 0) return;
    if (x >= width or y >= height) return;

    const xu: usize = @intCast(x);
    const yu: usize = @intCast(y);
    const addr = xu + @as(usize, width) * (yu / 8);
    const mask: u8 = @as(u8, 1) << @as(u3, @intCast(yu & 7));

    if (color) {
        buffer[addr] |= mask;
    } else {
        buffer[addr] &= ~mask;
    }
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
        if (pos.x >= width or pos.y >= height) break;
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

pub fn drawRect(x: i16, y: i16, w: i16, h: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    drawHLine(x, y, w, color);
    if (h > 1) drawHLine(x, y + h - 1, w, color);
    if (h > 2) {
        drawVLine(x, y + 1, h - 2, color);
        if (w > 1) drawVLine(x + w - 1, y + 1, h - 2, color);
    }
}

pub fn fillRect(x: i16, y: i16, w: i16, h: i16, color: bool) void {
    if (w <= 0 or h <= 0) return;

    var row: i16 = 0;
    while (row < h) : (row += 1) {
        drawHLine(x, y + row, w, color);
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
