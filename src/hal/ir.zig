//! 38kHz 赤外線LEDの文字列送受信 HAL。
//!
//! 送信は任意 GPIO のソフトウェアキャリア、受信は VS1838B/TSOP 系の
//! 38kHz 復調済みデジタル出力を想定する。

const gpio = @import("gpio.zig");
const time = @import("time.zig");

pub const Error = error{
    Timeout,
    BadHeader,
    TooLong,
    CrcMismatch,
    MalformedPulse,
};

pub const max_payload_len: usize = 64;

const magic0: u8 = 'I';
const magic1: u8 = 'R';
const version: u8 = 1;

const leader_mark_us: u32 = 9000;
const leader_space_us: u32 = 4500;
const bit_mark_us: u32 = 560;
const zero_space_us: u32 = 560;
const one_space_us: u32 = 1690;
const trailer_mark_us: u32 = 560;

pub const Tx = struct {
    pin: gpio.Pin,
    active_high: bool = true,
    carrier_hz: u32 = 38_000,
    duty_percent: u8 = 33,
};

pub const Rx = struct {
    pin: gpio.Pin,
    active_low: bool = true,
};

pub fn initTx(tx: Tx) void {
    gpio.enablePortClock(tx.pin.port);
    tx.pin.configure(.output_pp_10mhz);
    setTx(tx, false);
}

pub fn initRx(rx: Rx) void {
    gpio.enablePortClock(rx.pin.port);
    rx.pin.configure(.input_pull);
    rx.pin.write(rx.active_low);
}

pub fn sendString(tx: Tx, text: []const u8) void {
    sendBytes(tx, text);
}

/// `bytes` の先頭 `max_payload_len` バイトまでを IRText v1 フレームで送る。
pub fn sendBytes(tx: Tx, bytes: []const u8) void {
    const len: u8 = if (bytes.len > max_payload_len) max_payload_len else @intCast(bytes.len);

    mark(tx, leader_mark_us);
    space(tx, leader_space_us);

    var crc: u8 = 0;
    sendByte(tx, magic0);
    sendByte(tx, magic1);
    sendByte(tx, version);
    crc = crc8Update(crc, version);
    sendByte(tx, len);
    crc = crc8Update(crc, len);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const b = bytes[i];
        sendByte(tx, b);
        crc = crc8Update(crc, b);
    }
    sendByte(tx, crc);
    mark(tx, trailer_mark_us);
    setTx(tx, false);
}

pub fn recvBytes(rx: Rx, out: []u8, timeout_us: u32) Error![]u8 {
    const deadline = Deadline.start(timeout_us);

    const lm = try measurePulse(rx, true, deadline);
    if (!near(lm, leader_mark_us)) return Error.BadHeader;
    const ls = try measurePulse(rx, false, deadline);
    if (!near(ls, leader_space_us)) return Error.BadHeader;

    if ((try recvByte(rx, deadline)) != magic0) return Error.BadHeader;
    if ((try recvByte(rx, deadline)) != magic1) return Error.BadHeader;
    if ((try recvByte(rx, deadline)) != version) return Error.BadHeader;

    var crc: u8 = 0;
    crc = crc8Update(crc, version);

    const len = try recvByte(rx, deadline);
    crc = crc8Update(crc, len);
    if (len > max_payload_len or len > out.len) return Error.TooLong;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const b = try recvByte(rx, deadline);
        out[i] = b;
        crc = crc8Update(crc, b);
    }

    const received_crc = try recvByte(rx, deadline);
    if (received_crc != crc) return Error.CrcMismatch;

    const tm = try measurePulse(rx, true, deadline);
    if (!near(tm, trailer_mark_us)) return Error.MalformedPulse;

    return out[0..len];
}

fn sendByte(tx: Tx, b: u8) void {
    var bit: u3 = 0;
    while (true) : (bit +%= 1) {
        sendBit(tx, (b & (@as(u8, 1) << bit)) != 0);
        if (bit == 7) break;
    }
}

fn sendBit(tx: Tx, one: bool) void {
    mark(tx, bit_mark_us);
    space(tx, if (one) one_space_us else zero_space_us);
}

fn mark(tx: Tx, duration_us: u32) void {
    const period_us = @max(@as(u32, 1), 1_000_000 / tx.carrier_hz);
    const on_us = @max(@as(u32, 1), period_us * tx.duty_percent / 100);
    const off_us = @max(@as(u32, 1), period_us - on_us);
    const start = time.nowCycles();

    while (time.elapsedUsSince(start) < duration_us) {
        setTx(tx, true);
        time.delayUs(on_us);
        setTx(tx, false);
        time.delayUs(off_us);
    }
    setTx(tx, false);
}

fn space(tx: Tx, duration_us: u32) void {
    setTx(tx, false);
    time.delayUs(duration_us);
}

fn setTx(tx: Tx, active: bool) void {
    tx.pin.write(if (tx.active_high) active else !active);
}

fn recvByte(rx: Rx, deadline: Deadline) Error!u8 {
    var b: u8 = 0;
    var bit: u3 = 0;
    while (true) : (bit +%= 1) {
        const mark_us = try measurePulse(rx, true, deadline);
        if (!near(mark_us, bit_mark_us)) return Error.MalformedPulse;

        const space_us = try measurePulse(rx, false, deadline);
        if (near(space_us, zero_space_us)) {
            // zero bit
        } else if (near(space_us, one_space_us)) {
            b |= @as(u8, 1) << bit;
        } else {
            return Error.MalformedPulse;
        }

        if (bit == 7) break;
    }
    return b;
}

fn measurePulse(rx: Rx, mark_level: bool, deadline: Deadline) Error!u32 {
    try waitForLevel(rx, mark_level, deadline);

    const start = time.nowCycles();
    while (isMark(rx) == mark_level) {
        if (deadline.expired()) return Error.Timeout;
    }
    return time.elapsedUsSince(start);
}

fn waitForLevel(rx: Rx, mark_level: bool, deadline: Deadline) Error!void {
    while (isMark(rx) != mark_level) {
        if (deadline.expired()) return Error.Timeout;
    }
}

fn isMark(rx: Rx) bool {
    return if (rx.active_low) !rx.pin.read() else rx.pin.read();
}

fn near(actual: u32, expected: u32) bool {
    const min = expected * 70 / 100;
    const max = expected * 130 / 100;
    return actual >= min and actual <= max;
}

fn crc8Update(initial: u8, byte: u8) u8 {
    var crc = initial ^ byte;
    var i: u3 = 0;
    while (true) : (i +%= 1) {
        if ((crc & 0x01) != 0) {
            crc = (crc >> 1) ^ 0x8C;
        } else {
            crc >>= 1;
        }
        if (i == 7) break;
    }
    return crc;
}

const Deadline = struct {
    start_cycles: u32,
    timeout_us: u32,

    fn start(timeout_us: u32) Deadline {
        return .{
            .start_cycles = time.nowCycles(),
            .timeout_us = timeout_us,
        };
    }

    fn expired(self: Deadline) bool {
        return time.elapsedUsSince(self.start_cycles) >= self.timeout_us;
    }
};
