//! 38kHz 赤外線LEDの文字列送受信 HAL。
//!
//! 送信は任意 GPIO のソフトウェアキャリア、または PC4/TIM1_CH4 の
//! ハードウェアPWMを使用できる。受信は38kHz復調済みデジタル出力を想定する。

const gpio = @import("gpio.zig");
const pwm = @import("pwm.zig");
const time = @import("time.zig");
const system = @import("../system/system.zig");

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
const pulse_timeout_us: u32 = 20_000;

pub const CarrierMode = enum {
    software,
    tim1_ch4_pc4,
};

pub const Tx = struct {
    pin: gpio.Pin,
    active_high: bool = true,
    carrier_hz: u32 = 38_000,
    duty_percent: u8 = 33,
    carrier_mode: CarrierMode = .software,
};

pub const Rx = struct {
    pin: gpio.Pin,
    active_low: bool = true,
};

/// Optional cooperative observer for inputs that must remain responsive while
/// the bit-banged IR routines are waiting for or emitting pulses.
pub const ActivityHook = *const fn () callconv(.c) void;
var activity_hook: ?ActivityHook = null;

pub fn setActivityHook(hook: ?ActivityHook) void {
    activity_hook = hook;
}

fn observeActivity() void {
    if (activity_hook) |hook| hook();
}

pub fn initTx(tx: Tx) void {
    gpio.enablePortClock(tx.pin.port);
    switch (tx.carrier_mode) {
        .software => {
            tx.pin.configure(.output_pp_10mhz);
            setTx(tx, false);
        },
        .tim1_ch4_pc4 => {
            // TIM1_CH4 is mapped to PC4 on CH32V003J4M6.
            tx.pin.configure(.output_pp_10mhz);
            tx.pin.write(false);

            const counts_u32 = @max(
                @as(u32, 2),
                (system.core_clock_hz + tx.carrier_hz / 2) / tx.carrier_hz,
            );
            const counts: u16 = @intCast(@min(counts_u32, @as(u32, 65_535)));
            const duty: u16 = @intCast(@max(
                @as(u32, 1),
                @as(u32, counts) * @min(@as(u32, tx.duty_percent), 100) / 100,
            ));

            pwm.tim1.init(.{ .period = counts - 1, .prescaler = 0 });
            pwm.tim1.setDuty(.ch4, duty);
            pwm.tim1.setActiveHigh(.ch4, tx.active_high);
            pwm.tim1.disableChannel(.ch4);
            tx.pin.configure(.output_af_pp_10mhz);
        },
    }
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

/// Sends exactly 32 data bits, least-significant byte and bit first, using a
/// NEC-like leader and pulse-distance envelope.
pub fn sendPacket32(tx: Tx, packet: u32) void {
    mark(tx, leader_mark_us);
    space(tx, leader_space_us);

    var shift: u5 = 0;
    while (true) : (shift +%= 8) {
        sendByte(tx, @truncate(packet >> shift));
        if (shift == 24) break;
    }

    mark(tx, trailer_mark_us);
    setTx(tx, false);
}

/// Sends one state byte using the same NEC-like envelope as the wider packet
/// helpers. This compact form is useful for low-latency button/state links.
pub fn sendPacket8(tx: Tx, packet: u8) void {
    mark(tx, leader_mark_us);
    space(tx, leader_space_us);
    sendByte(tx, packet);
    mark(tx, trailer_mark_us);
    setTx(tx, false);
}

/// Receives the compact frame emitted by `sendPacket8`.
pub fn recvPacket8(rx: Rx, start_timeout_us: u32) Error!u8 {
    try waitForLeaderMark(rx, Deadline.start(start_timeout_us));

    const ls = try measurePulse(rx, false, pulseDeadline());
    if (!inRange(ls, 3_200, 5_800)) return Error.BadHeader;

    const packet = try recvByte(rx);
    const tm = try measurePulse(rx, true, pulseDeadline());
    if (!validBitMark(tm)) return Error.MalformedPulse;
    return packet;
}

/// Receives the fixed-size frame emitted by `sendPacket32`.
pub fn recvPacket32(rx: Rx, start_timeout_us: u32) Error!u32 {
    try waitForLeaderMark(rx, Deadline.start(start_timeout_us));

    const ls = try measurePulse(rx, false, pulseDeadline());
    if (!inRange(ls, 3_200, 5_800)) return Error.BadHeader;

    var packet: u32 = 0;
    var shift: u5 = 0;
    while (true) : (shift +%= 8) {
        packet |= @as(u32, try recvByte(rx)) << shift;
        if (shift == 24) break;
    }

    const tm = try measurePulse(rx, true, pulseDeadline());
    if (!validBitMark(tm)) return Error.MalformedPulse;
    return packet;
}

/// Sends exactly 64 data bits, least-significant byte and bit first.
pub fn sendPacket64(tx: Tx, packet: u64) void {
    mark(tx, leader_mark_us);
    space(tx, leader_space_us);

    var shift: u6 = 0;
    while (true) : (shift +%= 8) {
        sendByte(tx, @truncate(packet >> shift));
        if (shift == 56) break;
    }

    mark(tx, trailer_mark_us);
    setTx(tx, false);
}

/// Receives the fixed-size frame emitted by `sendPacket64`.
pub fn recvPacket64(rx: Rx, start_timeout_us: u32) Error!u64 {
    try waitForLeaderMark(rx, Deadline.start(start_timeout_us));

    const ls = try measurePulse(rx, false, pulseDeadline());
    if (!inRange(ls, 3_200, 5_800)) return Error.BadHeader;

    var packet: u64 = 0;
    var shift: u6 = 0;
    while (true) : (shift +%= 8) {
        packet |= @as(u64, try recvByte(rx)) << shift;
        if (shift == 56) break;
    }

    const tm = try measurePulse(rx, true, pulseDeadline());
    if (!validBitMark(tm)) return Error.MalformedPulse;
    return packet;
}

/// Sends an eight-byte fixed frame without requiring 64-bit arithmetic in
/// the application.
pub fn sendFrame8(tx: Tx, frame: *const [8]u8) void {
    mark(tx, leader_mark_us);
    space(tx, leader_space_us);
    for (frame) |byte| sendByte(tx, byte);
    mark(tx, trailer_mark_us);
    setTx(tx, false);
}

/// Receives an eight-byte fixed frame into caller-provided storage.
pub fn recvFrame8(rx: Rx, out: *[8]u8, start_timeout_us: u32) Error!void {
    try waitForLeaderMark(rx, Deadline.start(start_timeout_us));

    const ls = try measurePulse(rx, false, pulseDeadline());
    if (!inRange(ls, 3_200, 5_800)) return Error.BadHeader;

    for (out) |*byte| byte.* = try recvByte(rx);

    const tm = try measurePulse(rx, true, pulseDeadline());
    if (!validBitMark(tm)) return Error.MalformedPulse;
}

/// Waits up to `start_timeout_us` for a frame to begin. Once detected, pulse
/// decoding uses an independent timeout for each pulse.
pub fn recvBytes(rx: Rx, out: []u8, start_timeout_us: u32) Error![]u8 {
    // `timeout_us` only limits how long we wait for the start of a frame.
    // Once a leader is found, each pulse gets its own timeout so a valid
    // frame cannot expire merely because its complete payload is long.
    const start_deadline = Deadline.start(start_timeout_us);

    try waitForLeaderMark(rx, start_deadline);
    const ls = try measurePulse(rx, false, pulseDeadline());
    if (!near(ls, leader_space_us)) return Error.BadHeader;

    if ((try recvByte(rx)) != magic0) return Error.BadHeader;
    if ((try recvByte(rx)) != magic1) return Error.BadHeader;
    if ((try recvByte(rx)) != version) return Error.BadHeader;

    var crc: u8 = 0;
    crc = crc8Update(crc, version);

    const len = try recvByte(rx);
    crc = crc8Update(crc, len);
    if (len > max_payload_len or len > out.len) return Error.TooLong;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const b = try recvByte(rx);
        out[i] = b;
        crc = crc8Update(crc, b);
    }

    const received_crc = try recvByte(rx);
    if (received_crc != crc) return Error.CrcMismatch;

    const tm = try measurePulse(rx, true, pulseDeadline());
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
    switch (tx.carrier_mode) {
        .software => {
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
        },
        .tim1_ch4_pc4 => {
            setTx(tx, true);
            time.delayUs(duration_us);
        },
    }
    setTx(tx, false);
    observeActivity();
}

fn space(tx: Tx, duration_us: u32) void {
    setTx(tx, false);
    time.delayUs(duration_us);
    observeActivity();
}

fn setTx(tx: Tx, active: bool) void {
    switch (tx.carrier_mode) {
        .software => tx.pin.write(if (tx.active_high) active else !active),
        .tim1_ch4_pc4 => {
            if (active) {
                pwm.tim1.enableChannel(.ch4);
            } else {
                pwm.tim1.disableChannel(.ch4);
            }
        },
    }
}

fn recvByte(rx: Rx) Error!u8 {
    var b: u8 = 0;
    var bit: u3 = 0;
    while (true) : (bit +%= 1) {
        const mark_us = try measurePulse(rx, true, pulseDeadline());
        if (!validBitMark(mark_us)) return Error.MalformedPulse;

        const space_us = try measurePulse(rx, false, pulseDeadline());
        if (inRange(space_us, 300, 950)) {
            // zero bit
        } else if (inRange(space_us, 1_100, 2_300)) {
            b |= @as(u8, 1) << bit;
        } else {
            return Error.MalformedPulse;
        }

        if (bit == 7) break;
    }
    return b;
}

fn validBitMark(actual: u32) bool {
    return inRange(actual, 300, 850);
}

fn inRange(actual: u32, min: u32, max: u32) bool {
    return actual >= min and actual <= max;
}

fn pulseDeadline() Deadline {
    return Deadline.start(pulse_timeout_us);
}

fn measurePulse(rx: Rx, mark_level: bool, deadline: Deadline) Error!u32 {
    try waitForLevel(rx, mark_level, deadline);

    const start = time.nowCycles();
    while (isMark(rx) == mark_level) {
        observeActivity();
        if (deadline.expired()) return Error.Timeout;
    }
    return time.elapsedUsSince(start);
}

/// Skips short marks and frame fragments until a valid leader is found.
/// Keeping one start deadline prevents continuous noise from blocking forever.
fn waitForLeaderMark(rx: Rx, deadline: Deadline) Error!void {
    while (true) {
        const mark_us = try measurePulse(rx, true, deadline);
        if (inRange(mark_us, 7_000, 11_000)) return;
        if (deadline.expired()) return Error.Timeout;
    }
}

fn waitForLevel(rx: Rx, mark_level: bool, deadline: Deadline) Error!void {
    while (isMark(rx) != mark_level) {
        observeActivity();
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
