//! 圧電ブザー向け簡易トーン出力。 TIM2 を使う前提。
//!
//! 想定配線: ブザーの片足を TIM2_CHn の AF ピンに、 他足を GND に。
//! 例: TIM2_CH1 = PD4 のとき、 ブザーを PD4 ↔ GND に繋ぐ。
//!
//! 使い方:
//!
//!   ```zig
//!   fun.gpio.pin(.D, 4).configure(.output_af_pp_10mhz); // TIM2_CH1 = PD4
//!   fun.tone.init(.ch1);
//!   fun.tone.play(440, 200);           // A4 を 200ms
//!   fun.tone.stop();
//!   ```

const std = @import("std");
const regs = @import("../periph/registers.zig");
const pwm = @import("pwm.zig");
const time = @import("time.zig");
const system = @import("../system/system.zig");

var active_channel: pwm.Channel = .ch1;
var prescaler_shift: u32 = 8; // 256 分周

/// TIM2 をブザー用に初期化。 channel は接続したチャネルを指定する。
pub fn init(channel: pwm.Channel) void {
    active_channel = channel;

    // クロック有効化と最小限のレジスタ初期化はここで行う。
    // 周期 (=周波数) は play() のたびに更新する。
    pwm.tim2.init(.{ .prescaler = (@as(u16, 1) << @as(u4, @intCast(prescaler_shift))) - 1, .period = 1000 });
    pwm.tim2.enableChannel(channel);
    silence();
}

fn silence() void {
    pwm.tim2.setDuty(active_channel, 0);
}

/// 指定周波数 (Hz) で鳴らし、 duration_ms 後に止める。 ブロッキング。
pub fn play(freq_hz: u32, duration_ms: u32) void {
    if (freq_hz == 0) {
        silence();
        time.delayMs(duration_ms);
        return;
    }

    const eff_clock = system.core_clock_hz >> @as(u5, @intCast(prescaler_shift));
    var period: u32 = eff_clock / freq_hz;
    if (period == 0) period = 1;
    if (period > 0xFFFF) period = 0xFFFF;

    pwm.tim2.setPeriod(@intCast(period - 1));
    // デューティ 50%
    pwm.tim2.setDuty(active_channel, @intCast(period / 2));

    time.delayMs(duration_ms);

    silence();
}

/// 明示的に音を止める。
pub fn stop() void {
    silence();
}
