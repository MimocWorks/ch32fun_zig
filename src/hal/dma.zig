//! DMA1 HAL（CH32V003、7 チャネル）。
//!
//! 周辺機能ごとに固定のチャネルが割り当てられている（TRM Table）:
//!     ch1 = ADC1
//!     ch2 = SPI1_RX
//!     ch3 = SPI1_TX
//!     ch4 = USART1_TX
//!     ch5 = USART1_RX
//!     ch6 = (I2C1_TX 等)
//!     ch7 = (I2C1_RX 等)
//!
//! 典型的な使い方（メモリ → 周辺、例: SPI1_TX）:
//!
//!   ```zig
//!   fun.dma.init();
//!   fun.dma.startMemToPeriph(.spi1_tx, .{
//!       .periph_addr = fun.spi.dataRegisterAddress(),
//!       .mem = &buffer,
//!       .periph_size = .byte,
//!       .mem_size = .byte,
//!   });
//!   while (!fun.dma.isComplete(.spi1_tx)) {}
//!   fun.dma.clear(.spi1_tx);
//!   ```

const regs = @import("../periph/registers.zig");

/// 固定割り当てのチャネル。値は DMA チャネル番号 (1..7)。
pub const Channel = enum(u3) {
    adc1 = 1,
    spi1_rx = 2,
    spi1_tx = 3,
    usart1_tx = 4,
    usart1_rx = 5,
    ch6 = 6,
    ch7 = 7,
};

/// 転送幅。周辺側・メモリ側それぞれに指定する。
pub const Width = enum { byte, half_word, word };

pub const Transfer = struct {
    /// 周辺レジスタのアドレス（例: SPI1 DATAR, USART1 DATAR, ADC1 RDATAR）。
    periph_addr: u32,
    /// メモリ側バッファ。要素数が転送回数になる。
    mem: []const u8,
    periph_size: Width = .byte,
    mem_size: Width = .byte,
    /// メモリアドレスを 1 要素ごとに進めるか（通常 true）。
    mem_increment: bool = true,
    /// 周辺アドレスを進めるか（FIFO 相手なら false）。
    periph_increment: bool = false,
    /// バッファ末尾で先頭に戻る循環転送（連続再送に便利）。
    circular: bool = false,
    /// 完了割り込みを上げるか。
    interrupt: bool = false,
};

pub fn init() void {
    const rcc = regs.rcc();
    rcc.AHBPCENR |= regs.RCC_AHB_DMA1;
}

fn ch(channel: Channel) *volatile regs.DmaChannelRegs {
    const d = regs.dma1();
    return &d.channels[@intFromEnum(channel) - 1];
}

fn widthBitsPeriph(w: Width) u32 {
    return switch (w) {
        .byte => regs.DMA_CFGR_PSIZE_8,
        .half_word => regs.DMA_CFGR_PSIZE_16,
        .word => regs.DMA_CFGR_PSIZE_32,
    };
}

fn widthBitsMem(w: Width) u32 {
    return switch (w) {
        .byte => regs.DMA_CFGR_MSIZE_8,
        .half_word => regs.DMA_CFGR_MSIZE_16,
        .word => regs.DMA_CFGR_MSIZE_32,
    };
}

/// メモリ → 周辺の転送を構成して開始する。
pub fn startMemToPeriph(channel: Channel, t: Transfer) void {
    const c = ch(channel);

    // 構成中はチャネルを止めておく。
    c.CFGR &= ~regs.DMA_CFGR_EN;

    c.PADDR = t.periph_addr;
    c.MADDR = @intFromPtr(t.mem.ptr);
    c.CNTR = t.mem.len;

    var cfg: u32 = regs.DMA_CFGR_DIR_MEM2PERIPH | regs.DMA_CFGR_PL_HIGH;
    cfg |= widthBitsPeriph(t.periph_size);
    cfg |= widthBitsMem(t.mem_size);
    if (t.mem_increment) cfg |= regs.DMA_CFGR_MINC;
    if (t.periph_increment) cfg |= regs.DMA_CFGR_PINC;
    if (t.circular) cfg |= regs.DMA_CFGR_CIRC;
    if (t.interrupt) cfg |= regs.DMA_CFGR_TCIE;

    c.CFGR = cfg;
    c.CFGR |= regs.DMA_CFGR_EN;
}

/// 周辺 → メモリの転送を構成して開始する（受信用; `mem` は書き込み先）。
pub fn startPeriphToMem(channel: Channel, periph_addr: u32, mem: []u8, opts: struct {
    periph_size: Width = .byte,
    mem_size: Width = .byte,
    circular: bool = false,
    interrupt: bool = false,
}) void {
    const c = ch(channel);
    c.CFGR &= ~regs.DMA_CFGR_EN;

    c.PADDR = periph_addr;
    c.MADDR = @intFromPtr(mem.ptr);
    c.CNTR = mem.len;

    var cfg: u32 = regs.DMA_CFGR_PL_HIGH | regs.DMA_CFGR_MINC; // DIR=0 → periph→mem
    cfg |= widthBitsPeriph(opts.periph_size);
    cfg |= widthBitsMem(opts.mem_size);
    if (opts.circular) cfg |= regs.DMA_CFGR_CIRC;
    if (opts.interrupt) cfg |= regs.DMA_CFGR_TCIE;

    c.CFGR = cfg;
    c.CFGR |= regs.DMA_CFGR_EN;
}

/// 転送完了（TCIF）が立っているか。
pub fn isComplete(channel: Channel) bool {
    const d = regs.dma1();
    return (d.INTFR & regs.dmaChannelTcifBit(@intFromEnum(channel))) != 0;
}

/// このチャネルの割り込みフラグをクリアする。
pub fn clear(channel: Channel) void {
    const d = regs.dma1();
    d.INTFCR = regs.dmaChannelGifBit(@intFromEnum(channel));
}

/// チャネルを停止する。
pub fn stop(channel: Channel) void {
    const c = ch(channel);
    c.CFGR &= ~regs.DMA_CFGR_EN;
}

/// 残り転送回数（CNTR）。
pub fn remaining(channel: Channel) u32 {
    return ch(channel).CNTR;
}
