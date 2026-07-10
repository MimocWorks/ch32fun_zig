//! 38kHz 赤外線LEDで "HELLO CH32" を送信し、復調済みIR受信モジュールで
//! IRText v1 フレームを受信する。
//!
//! 配線:
//! - IR LED: PD0 -> 抵抗 -> IR LED -> GND
//! - IR receiver OUT: PD1
//! - Status LED: PD2 -> 抵抗 -> LED -> GND
//!
//! 2台のボードで片方を送信側、もう片方を受信側として使う場合は
//! `role` を `.tx` / `.rx` に変更してビルドする。

const fun = @import("ch32fun");

const Role = enum { tx, rx, loopback };
const role: Role = .loopback;

const tx = fun.ir.Tx{ .pin = fun.gpio.pin(.D, 0) };
const rx = fun.ir.Rx{ .pin = fun.gpio.pin(.D, 1) };
const status_led = fun.gpio.pin(.D, 2);

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.ir.initTx(tx);
    fun.ir.initRx(rx);
    status_led.configure(.output_pp_10mhz);

    switch (role) {
        .tx => runTx(),
        .rx => runRx(),
        .loopback => runLoopback(),
    }
}

fn runTx() noreturn {
    while (true) {
        fun.ir.sendString(tx, "HELLO CH32");
        blink(1);
        fun.time.delayMs(1000);
    }
}

fn runRx() noreturn {
    var buf: [fun.ir.max_payload_len]u8 = undefined;
    while (true) {
        if (fun.ir.recvBytes(rx, &buf, 120_000)) |msg| {
            blink(@max(@as(u8, 1), @as(u8, @intCast(msg.len & 0x7))));
        } else |_| {
            status_led.write(false);
        }
    }
}

fn runLoopback() noreturn {
    var buf: [fun.ir.max_payload_len]u8 = undefined;
    while (true) {
        fun.ir.sendString(tx, "HELLO CH32");
        if (fun.ir.recvBytes(rx, &buf, 120_000)) |msg| {
            blink(@max(@as(u8, 1), @as(u8, @intCast(msg.len & 0x7))));
        } else |_| {
            blink(1);
        }
        fun.time.delayMs(1000);
    }
}

fn blink(count: u8) void {
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        status_led.write(true);
        fun.time.delayMs(60);
        status_led.write(false);
        fun.time.delayMs(120);
    }
}
