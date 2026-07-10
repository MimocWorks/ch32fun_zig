//! TIM1 / TIM2 を使った PWM 出力。
//!
//! TIM1 は APB2 系、 TIM2 は APB1 系。 CH32V003 ではどちらも HCLK で動く。
//!
//! 典型的な使い方:
//!
//!   ```
//!   const pwm = fun.pwm;
//!   fun.gpio.pin(.D, 2).configure(.output_af_pp_10mhz); // TIM1_CH1 = PD2
//!   pwm.tim1.init(.{ .period = 1000, .prescaler = 48 }); // ~1kHz
//!   pwm.tim1.enableChannel(.ch1);
//!   pwm.tim1.setDuty(.ch1, 500); // 50%
//!   ```
//!
//! period に対する CHxCVR の比率がデューティになる。

const regs = @import("../periph/registers.zig");

pub const Channel = enum(u2) { ch1 = 0, ch2 = 1, ch3 = 2, ch4 = 3 };

pub const Config = struct {
    /// ATRLR (Auto-Reload) = 1 周期に対応するカウント
    period: u16 = 1000,
    /// PSC = プリスケーラ。 実効カウントクロック = HCLK / (prescaler + 1)
    prescaler: u16 = 0,
};

fn Timer(comptime is_advanced: bool, comptime regs_fn: anytype, comptime rcc_apb: enum { apb1, apb2 }, comptime apb_bit: u32) type {
    return struct {
        pub fn init(cfg: Config) void {
            const rcc = regs.rcc();
            switch (rcc_apb) {
                .apb1 => rcc.APB1PCENR |= apb_bit,
                .apb2 => rcc.APB2PCENR |= apb_bit,
            }

            const t = regs_fn();
            t.CTLR1 = 0;
            t.PSC = cfg.prescaler;
            t.ATRLR = cfg.period;
            t.CNT = 0;

            // 全チャネルとも PWM mode 1 + プリロード有効に統一しておく
            t.CHCTLR1 = regs.TIM_CHCTLR_OC_PWM1_PRELOAD | regs.TIM_CHCTLR_OC_PWM1_PRELOAD_HI;
            t.CHCTLR2 = regs.TIM_CHCTLR_OC_PWM1_PRELOAD | regs.TIM_CHCTLR_OC_PWM1_PRELOAD_HI;
            t.CCER = 0;

            if (is_advanced) {
                // TIM1 (Advanced) は MOE を立てないと出力が出ない
                t.BDTR = regs.TIM_BDTR_MOE;
            }

            // ATRLR 更新を即座に反映するために UG を蹴る
            t.SWEVGR = 1;

            t.CTLR1 = regs.TIM_CTLR1_ARPE | regs.TIM_CTLR1_CEN;
        }

        pub fn enableChannel(ch: Channel) void {
            const t = regs_fn();
            const bit: u16 = switch (ch) {
                .ch1 => regs.TIM_CCER_CC1E,
                .ch2 => regs.TIM_CCER_CC2E,
                .ch3 => regs.TIM_CCER_CC3E,
                .ch4 => regs.TIM_CCER_CC4E,
            };
            t.CCER |= bit;
        }

        pub fn setDuty(ch: Channel, value: u16) void {
            const t = regs_fn();
            switch (ch) {
                .ch1 => t.CH1CVR = value,
                .ch2 => t.CH2CVR = value,
                .ch3 => t.CH3CVR = value,
                .ch4 => t.CH4CVR = value,
            }
        }

        pub fn setPeriod(period: u16) void {
            regs_fn().ATRLR = period;
        }

        pub fn stop() void {
            regs_fn().CTLR1 &= ~regs.TIM_CTLR1_CEN;
        }
    };
}

pub const tim1 = Timer(true, regs.tim1, .apb2, regs.RCC_APB2_TIM1);
pub const tim2 = Timer(false, regs.tim2, .apb1, regs.RCC_APB1_TIM2);
