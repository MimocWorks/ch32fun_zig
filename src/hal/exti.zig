//! EXTI (External Interrupt) HAL。
//!
//! GPIO ピンの立ち上がり / 立ち下がり / 両エッジで割り込みを発生させる。
//! CH32V003 では EXTI ライン番号 = GPIO ピン番号 (0..7) で、
//! どのポート (A/C/D) のそのピンを使うかは AFIO.EXTICR で選ぶ。
//!
//! 使い方:
//!
//!   ```zig
//!   fun.input.initButtonPd1Pullup();  // PD1 を入力 + プルアップに
//!   fun.exti.config(.{ .port = .D, .line = 1, .trigger = .falling, .handler = onPress });
//!   fun.exti.enable(1);
//!   fun.system.enableInterrupts();
//!   ```
//!
//! ハンドラ本体は startup.zig の vector_table から `_exti7_0_irq_entry`
//! 経由で呼ばれる。

const regs = @import("../periph/registers.zig");
const gpio = @import("gpio.zig");

pub const Port = gpio.Port;

pub const Trigger = enum { rising, falling, both };

pub const Handler = *const fn (line: u8) callconv(.c) void;

pub const Config = struct {
    port: Port,
    line: u4,
    trigger: Trigger,
    handler: Handler,
};

var handlers: [8]?Handler = .{null} ** 8;

/// 指定ラインに対する設定を行う (有効化はまだしない)。
pub fn config(cfg: Config) void {
    const rcc = regs.rcc();
    rcc.APB2PCENR |= regs.RCC_APB2_AFIO;

    // AFIO.EXTICR は 4 ライン × 2-bit を 1 レジスタに詰めている。
    // CH32V003 では line 0..7 用に下位 16-bit (= EXTICR の下半分) を使う。
    const a = regs.afio();
    const shift: u5 = @as(u5, cfg.line) * 2;
    const port_code: u32 = switch (cfg.port) {
        .A => 0,
        .C => 2,
        .D => 3,
    };
    a.EXTICR = (a.EXTICR & ~(@as(u32, 0x3) << shift)) | (port_code << shift);

    const e = regs.exti();
    const bit: u32 = @as(u32, 1) << cfg.line;
    switch (cfg.trigger) {
        .rising => {
            e.RTENR |= bit;
            e.FTENR &= ~bit;
        },
        .falling => {
            e.FTENR |= bit;
            e.RTENR &= ~bit;
        },
        .both => {
            e.RTENR |= bit;
            e.FTENR |= bit;
        },
    }

    handlers[cfg.line] = cfg.handler;
}

/// 割り込みを有効化する。 PFIC 側のラインも同時に立てる。
pub fn enable(line: u4) void {
    const e = regs.exti();
    e.INTENR |= @as(u32, 1) << line;
    // CH32V003 では EXTI0..7 は同一 IRQ (EXTI7_0_IRQn = 20) で来る
    regs.pficEnableIrq(regs.IrqExti7_0);
}

pub fn disable(line: u4) void {
    const e = regs.exti();
    e.INTENR &= ~(@as(u32, 1) << line);
}

/// 割り込みコンテキストから呼ばれる。 立っているフラグを 1 つずつ処理する。
pub fn handleInterrupt() callconv(.c) void {
    const e = regs.exti();
    var pending = e.INTFR;
    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        const bit: u32 = @as(u32, 1) << @as(u5, @intCast(i));
        if ((pending & bit) != 0) {
            e.INTFR = bit;
            if (handlers[i]) |h| h(i);
            pending &= ~bit;
        }
    }
}
