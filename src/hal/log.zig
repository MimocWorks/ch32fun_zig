//! `std.fmt.bufPrint` + UART で「printf 風」 ログを実現する薄いラッパ。
//!
//! 内部で 96 バイトの静的バッファを 1 本持ち、 そこに整形して UART で吐く。
//! バッファあふれは無視 (切り詰め)。 割り込みコンテキストから呼ぶのは非推奨
//! (UART がブロックしている間、 割り込みハンドラが寝てしまうため)。

const std = @import("std");
const uart = @import("uart.zig");

var line_buf: [96]u8 = undefined;

pub const Level = enum {
    info,
    warn,
    err,
};

fn prefix(level: Level) []const u8 {
    return switch (level) {
        .info => "[I] ",
        .warn => "[W] ",
        .err => "[E] ",
    };
}

/// `init(baud)` で UART を起こす。 既に uart.init を呼んでいるなら不要。
pub fn init(baud: u32) void {
    uart.init(baud);
}

pub fn print(level: Level, comptime fmt: []const u8, args: anytype) void {
    uart.writeAll(prefix(level));
    const written = std.fmt.bufPrint(&line_buf, fmt, args) catch line_buf[0..0];
    uart.writeAll(written);
    uart.writeAll("\r\n");
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    print(.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    print(.warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    print(.err, fmt, args);
}

/// 生バイト列をそのまま吐く (改行なし)。
pub fn raw(bytes: []const u8) void {
    uart.writeAll(bytes);
}
