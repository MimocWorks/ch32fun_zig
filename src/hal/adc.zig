//! ADC1 単発変換 HAL。
//!
//! - 10-bit 右詰め、 単一チャネル変換、 ソフトウェアトリガ
//! - 入力ピンはチャネル番号で指定 (CH32V003 のチャネルマップに従う):
//!     ch0 = PA2, ch1 = PA1, ch2 = PC4, ch3 = PD2,
//!     ch4 = PD3, ch5 = PD5, ch6 = PD6, ch7 = PD4
//!
//! 使い方:
//!
//!   ```zig
//!   fun.gpio.pin(.D, 2).configure(.input_analog); // ch3 = PD2
//!   fun.adc.init();
//!   const raw = fun.adc.readSingle(3);   // 0..1023
//!   ```

const regs = @import("../periph/registers.zig");
const time = @import("time.zig");

pub const max_value: u16 = 1023;

pub fn init() void {
    const rcc = regs.rcc();
    rcc.APB2PCENR |= regs.RCC_APB2_ADC1;

    const a = regs.adc1();

    // パワーオン
    a.CTLR2 = regs.ADC_CTLR2_ADON;
    // 安定するまで少し待つ
    time.delayMs(1);

    // キャリブレーション
    a.CTLR2 |= regs.ADC_CTLR2_RSTCAL;
    while ((a.CTLR2 & regs.ADC_CTLR2_RSTCAL) != 0) {}
    a.CTLR2 |= regs.ADC_CTLR2_CAL;
    while ((a.CTLR2 & regs.ADC_CTLR2_CAL) != 0) {}

    // ソフトウェアトリガを選択 + 外部トリガ有効
    a.CTLR2 |= regs.ADC_CTLR2_EXTSEL_SWSTART | regs.ADC_CTLR2_EXTTRIG;

    // 全チャネルとも最大サンプル時間 (= 約 241 サイクル) に
    // SAMPTR1: ch10..18 用 (CH32V003 では未使用)
    // SAMPTR2: ch0..9   用、 各 3-bit
    a.SAMPTR2 = 0o77777777; // 8 進 = 各 3-bit 全部 7 (241 cycles)
}

/// channel は 0..7 (CH32V003 の場合)。
pub fn readSingle(channel: u8) u16 {
    const a = regs.adc1();
    // RSQR3 の下位 5-bit に変換チャネルを 1 個セット (シーケンス長 = 1)
    a.RSQR1 = 0; // L[3:0]=0 → シーケンス長 1
    a.RSQR3 = @as(u32, channel) & 0x1F;

    // ソフトウェアスタート
    a.CTLR2 |= regs.ADC_CTLR2_SWSTART;
    while ((a.STATR & regs.ADC_STATR_EOC) == 0) {}
    return @intCast(a.RDATAR & 0x3FF);
}

/// `samples` 回読んで平均を取る簡易ノイズ抑制。
pub fn readAveraged(channel: u8, samples: u8) u16 {
    if (samples == 0) return readSingle(channel);
    var sum: u32 = 0;
    var i: u8 = 0;
    while (i < samples) : (i += 1) {
        sum += readSingle(channel);
    }
    return @intCast(sum / samples);
}
