//! USART1 ブロッキング送信専用 HAL。
//!
//! - TX ピン: PD5 (デフォルトリマップ無し)
//! - 8N1 固定、 受信は未サポート
//! - `system.init` で PLL を有効化したあと `init(baud)` を呼ぶ
//!
//! 受信が必要になったら CTLR1.RE を立てて DATAR を読む経路を追加すること。

const regs = @import("../periph/registers.zig");
const gpio = @import("gpio.zig");
const system = @import("../system/system.zig");

pub fn init(baud: u32) void {
    const rcc = regs.rcc();
    rcc.APB2PCENR |= regs.RCC_APB2_GPIOD | regs.RCC_APB2_USART1 | regs.RCC_APB2_AFIO;

    // PD5: AF push-pull 10MHz (TX)
    gpio.pin(.D, 5).configure(.output_af_pp_10mhz);

    const u = regs.usart1();
    // 一旦無効化
    u.CTLR1 = 0;
    // BRR = 整数分周。 CH32V003 は USART1 が APB2 = HCLK で供給される。
    // baudrate = HCLK / BRR
    u.BRR = system.core_clock_hz / baud;
    u.CTLR2 = 0;
    u.CTLR3 = 0;
    u.CTLR1 = regs.USART_CTLR1_UE | regs.USART_CTLR1_TE;
}

pub fn writeByte(b: u8) void {
    const u = regs.usart1();
    while ((u.STATR & regs.USART_STATR_TXE) == 0) {}
    u.DATAR = b;
}

pub fn writeAll(bytes: []const u8) void {
    for (bytes) |b| writeByte(b);
}

pub fn flush() void {
    const u = regs.usart1();
    while ((u.STATR & regs.USART_STATR_TC) == 0) {}
}

/// USART1 TX の DMA 要求 (CTLR3.DMAT) を有効化する。dma HAL と組み合わせて使う。
pub fn enableTxDma() void {
    const u = regs.usart1();
    u.CTLR3 |= @as(u32, 1) << 7; // DMAT
}

/// DATAR レジスタのアドレス（DMA の周辺アドレスに渡す）。
pub fn dataRegisterAddress() u32 {
    return regs.USART1_BASE + 0x04;
}
