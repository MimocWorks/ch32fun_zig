//! Debug-only formatted logging over the CH32V003 single-wire debug link.
//!
//! Compatible with ch32fun DebugPrintf and `minichlink -T`. Unless explicitly
//! enabled by the application, optimized builds remove all logging code.
//! Logging is blocking; do not use it in ISRs or timing-sensitive code. PD1 is
//! occupied by SWIO while a terminal is attached.

const builtin = @import("builtin");
const root = @import("root");

/// Debug builds enable logging by default. Applications may explicitly set
/// `pub const ch32fun_swio_log_enabled = true` to retain logs in an optimized
/// diagnostic build, or false to remove them even in Debug mode.
pub const enabled = if (@hasDecl(root, "ch32fun_swio_log_enabled"))
    root.ch32fun_swio_log_enabled
else
    builtin.mode == .debug;

pub const Level = enum { info, warn, err };

const dmdata0_address: usize = 0xe000_00f4;
const dmdata1_address: usize = 0xe000_00f8;
const busy_bit: u32 = 0x80;
const timed_out_mask: u32 = 0xc0;
// small can execute a short polling loop before minichlink has finished
// rebooting the target and entered terminal polling. Match ch32fun's optional
// long-wait configuration so early boot messages are not lost.
const timeout_iterations: u32 = 0x8000_0000;
// Some WCH-LinkE firmware/minichlink combinations do not return DMDATA1
// reliably during terminal polling. Restrict each handshake to the three
// payload bytes carried by DMDATA0 for robust output.
const max_chunk_len: usize = 3;

fn dmdata0() *volatile u32 {
    return @ptrFromInt(dmdata0_address);
}

fn dmdata1() *volatile u32 {
    return @ptrFromInt(dmdata1_address);
}

fn prefix(level: Level) []const u8 {
    return switch (level) {
        .info => "[I] ",
        .warn => "[W] ",
        .err => "[E] ",
    };
}

/// Initializes the ch32fun-compatible DMDATA handshake.
pub inline fn init() void {
    if (comptime enabled) {
        dmdata1().* = 0;
        dmdata0().* = busy_bit;
    }
}

/// Waits indefinitely for `minichlink -T` to acknowledge the initial
/// sentinel. Use this when early boot messages must not be lost. Firmware will
/// not progress if the terminal is never started.
pub inline fn waitForTerminal() void {
    if (comptime enabled) {
        while ((dmdata0().* & busy_bit) != 0) {}
    }
}

pub inline fn print(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (comptime enabled) {
        writeAllEnabled(prefix(level));
        formatArgs(fmt, args, 0, 0);
        writeAllEnabled("\r\n");
    }
}

pub inline fn info(comptime fmt: []const u8, args: anytype) void {
    if (comptime enabled) print(.info, fmt, args);
}

pub inline fn warn(comptime fmt: []const u8, args: anytype) void {
    if (comptime enabled) print(.warn, fmt, args);
}

pub inline fn err(comptime fmt: []const u8, args: anytype) void {
    if (comptime enabled) print(.err, fmt, args);
}

/// Writes bytes without a prefix or newline.
pub inline fn raw(bytes: []const u8) void {
    if (comptime enabled) writeAllEnabled(bytes);
}

const Placeholder = struct {
    open: usize,
    close: usize,
};

fn nextPlaceholder(comptime fmt: []const u8, comptime cursor: usize) ?Placeholder {
    var open = cursor;
    while (open < fmt.len and fmt[open] != '{') : (open += 1) {}
    if (open == fmt.len) return null;

    var close = open + 1;
    while (close < fmt.len and fmt[close] != '}') : (close += 1) {}
    if (comptime close == fmt.len) @compileError("SWIO log format has an unmatched '{'");
    return .{ .open = open, .close = close };
}

fn formatArgs(
    comptime fmt: []const u8,
    args: anytype,
    comptime arg_index: usize,
    comptime cursor: usize,
) void {
    if (comptime arg_index == args.len) {
        if (comptime nextPlaceholder(fmt, cursor) != null)
            @compileError("SWIO log format has more placeholders than arguments");
        writeAllEnabled(fmt[cursor..]);
        return;
    }

    const placeholder = comptime nextPlaceholder(fmt, cursor) orelse
        @compileError("SWIO log format has more arguments than placeholders");
    writeAllEnabled(fmt[cursor..placeholder.open]);
    writeValue(fmt[placeholder.open + 1 .. placeholder.close], args[arg_index]);
    formatArgs(fmt, args, arg_index + 1, placeholder.close + 1);
}

fn writeValue(comptime specifier: []const u8, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .int => |int_info| {
            if (specifier.len == 1 and specifier[0] == 'x') {
                writeUnsigned(@intCast(value), 16);
            } else if (specifier.len == 0 or
                (specifier.len == 1 and specifier[0] == 'd'))
            {
                if (int_info.signedness == .signed and value < 0) {
                    writeAllEnabled("-");
                    const signed_value: i64 = @intCast(value);
                    var magnitude: u64 = @intCast(-(signed_value + 1));
                    magnitude += 1;
                    writeUnsigned(magnitude, 10);
                } else {
                    writeUnsigned(@intCast(value), 10);
                }
            } else {
                @compileError("integer SWIO log values support only {}, {d}, and {x}");
            }
        },
        .comptime_int => {
            if (specifier.len == 1 and specifier[0] == 'x') {
                writeUnsigned(@intCast(value), 16);
            } else if (specifier.len == 0 or
                (specifier.len == 1 and specifier[0] == 'd'))
            {
                if (value < 0) {
                    writeAllEnabled("-");
                    writeUnsigned(@intCast(-value), 10);
                } else {
                    writeUnsigned(@intCast(value), 10);
                }
            } else {
                @compileError("integer SWIO log values support only {}, {d}, and {x}");
            }
        },
        .bool => writeAllEnabled(if (value) "true" else "false"),
        .enum_literal, .@"enum" => writeAllEnabled(@tagName(value)),
        .pointer, .array => {
            if (specifier.len == 0 or (specifier.len == 1 and specifier[0] == 's')) {
                writeAllEnabled(value);
            } else {
                @compileError("string SWIO log values support only {} and {s}");
            }
        },
        else => @compileError("unsupported SWIO log value type"),
    }
}

fn writeUnsigned(value: u64, base: u8) void {
    const digits = "0123456789abcdef";
    var buffer: [20]u8 = undefined;
    var remaining = value;
    var cursor: usize = buffer.len;

    while (true) {
        cursor -= 1;
        buffer[cursor] = digits[@intCast(remaining % base)];
        remaining /= base;
        if (remaining == 0) break;
    }
    writeAllEnabled(buffer[cursor..]);
}

fn writeAllEnabled(bytes: []const u8) void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const chunk_len: usize = @min(max_chunk_len, bytes.len - offset);
        if (!waitUntilReady()) return;

        var first_word: u32 = busy_bit | @as(u32, @intCast(chunk_len + @as(usize, 4)));
        const first_len = @min(@as(usize, 3), chunk_len);
        var i: usize = 0;
        while (i < first_len) : (i += 1) {
            const shift: u5 = @intCast((i + 1) * 8);
            first_word |= @as(u32, bytes[offset + i]) << shift;
        }

        var second_word: u32 = 0;
        i = 3;
        while (i < chunk_len) : (i += 1) {
            const shift: u5 = @intCast((i - 3) * 8);
            second_word |= @as(u32, bytes[offset + i]) << shift;
        }

        dmdata1().* = second_word;
        dmdata0().* = first_word;
        offset += chunk_len;
    }
}

fn waitUntilReady() bool {
    const data = dmdata0();
    if ((data.* & timed_out_mask) == timed_out_mask) return false;

    var remaining: u32 = timeout_iterations;
    while ((data.* & busy_bit) != 0) {
        if (remaining == 0) {
            data.* |= timed_out_mask;
            return false;
        }
        remaining -= 1;
    }
    return true;
}
