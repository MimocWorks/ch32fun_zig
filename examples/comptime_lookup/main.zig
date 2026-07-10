//! comptime_lookup
//!
//! comptime に sin テーブルを生成して ROM に焼き、 LED の輝度を「ゆっくり呼吸」
//! させる。
//!
//! Zig では `comptime` 内で浮動小数点演算 + std.math.sin を呼べる。
//! 結果はビルド時に `[N]u16` の配列リテラルになり、 ファームの `.rodata`
//! セクションに静的に置かれる。 つまり 実機の MCU 側では sin の計算は
//! 一切走らず、 単に配列インデックスでルックアップするだけ。
//!
//! - 256 エントリ、 各 u16、 = **512 バイト** を `.rodata` に置く
//! - 値域は 0..1000 (PWM の period に合わせて)
//! - ガンマ補正もかけて、 視覚的に滑らかな呼吸に
//!
//! 配線: LED アノード → 抵抗 → PD2 (TIM1_CH1)、 カソード → GND

const std = @import("std");
const fun = @import("ch32fun");

const table_len: usize = 256;
const pwm_period: u16 = 1000;
const gamma: f32 = 2.2;

/// comptime 関数。 戻り値は静的配列なので、 そのまま `const = comptime f();`
/// に渡せば ROM 上の配列リテラルが得られる。
fn buildBreathTable() [table_len]u16 {
    @setEvalBranchQuota(200_000);
    var out: [table_len]u16 = undefined;
    var i: usize = 0;
    while (i < table_len) : (i += 1) {
        const phase: f32 = @as(f32, @floatFromInt(i)) / @as(f32, table_len);
        // 0..1 の sin² で「呼吸」 のような滑らかな増減
        const s = @sin(phase * std.math.pi);
        const lin = s * s;
        // ガンマ補正で人間の知覚に合わせる
        const corrected = std.math.pow(f32, lin, gamma);
        const v = corrected * @as(f32, @floatFromInt(pwm_period));
        out[i] = @intFromFloat(@max(0.0, @min(@as(f32, @floatFromInt(pwm_period)), v)));
    }
    return out;
}

// このシンボルは ROM (= .rodata) に焼き込まれる。 実機のループから見れば、
// 単なる const 配列の参照になる。
const breath_table: [table_len]u16 = buildBreathTable();

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    // PD2 = TIM1_CH1
    fun.gpio.pin(.D, 2).configure(.output_af_pp_10mhz);
    fun.pwm.tim1.init(.{ .prescaler = 47, .period = pwm_period });
    fun.pwm.tim1.enableChannel(.ch1);

    var idx: u8 = 0;
    while (true) : (idx +%= 1) {
        fun.pwm.tim1.setDuty(.ch1, breath_table[idx]);
        fun.time.delayMs(15);
    }
}
