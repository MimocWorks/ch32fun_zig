//! SPI1 マスタ HAL（ブロッキング 8-bit 全二重）。
//!
//! CH32V003 の SPI1 はデフォルトのピン割り当てで:
//!     SCK  = PC5, MOSI = PC6, MISO = PC7, NSS(HW) = PC1
//!
//! NSS はソフトウェア管理 (SSM=1, SSI=1) を既定にしているので、チップセレクトは
//! 任意の GPIO で行う（複数スレーブを扱いやすい）。
//!
//! 使い方:
//!
//!   ```zig
//!   fun.gpio.pin(.C, 5).configure(.output_af_pp_30mhz); // SCK
//!   fun.gpio.pin(.C, 6).configure(.output_af_pp_30mhz); // MOSI
//!   fun.gpio.pin(.C, 7).configure(.input_pull);         // MISO
//!   fun.spi.init(.{ .baud = .div8, .mode = .mode0 });
//!   const cs = fun.gpio.pin(.C, 3);
//!   cs.configure(.output_pp_10mhz);
//!   cs.write(false);                  // select (active-low)
//!   const rx = fun.spi.transfer(0xAB);
//!   cs.write(true);                   // deselect
//!   ```

const regs = @import("../periph/registers.zig");

/// SCK 分周比。PCLK2 (= HCLK, 既定 48MHz) を 2^(n+1) で割る。
pub const Baud = enum(u3) {
    div2 = 0,
    div4 = 1,
    div8 = 2,
    div16 = 3,
    div32 = 4,
    div64 = 5,
    div128 = 6,
    div256 = 7,
};

/// クロック極性/位相の組み合わせ（標準の SPI mode 0..3）。
pub const Mode = enum {
    mode0, // CPOL=0, CPHA=0
    mode1, // CPOL=0, CPHA=1
    mode2, // CPOL=1, CPHA=0
    mode3, // CPOL=1, CPHA=1
};

pub const BitOrder = enum { msb_first, lsb_first };

pub const Config = struct {
    baud: Baud = .div8,
    mode: Mode = .mode0,
    bit_order: BitOrder = .msb_first,
};

pub fn init(config: Config) void {
    const rcc = regs.rcc();
    rcc.APB2PCENR |= regs.RCC_APB2_SPI1;

    const s = regs.spi1();

    var ctlr1: u16 = regs.SPI_CTLR1_MSTR |
        regs.SPI_CTLR1_SSM | regs.SPI_CTLR1_SSI;

    ctlr1 |= @as(u16, @intFromEnum(config.baud)) << regs.SPI_CTLR1_BR_SHIFT;

    switch (config.mode) {
        .mode0 => {},
        .mode1 => ctlr1 |= regs.SPI_CTLR1_CPHA,
        .mode2 => ctlr1 |= regs.SPI_CTLR1_CPOL,
        .mode3 => ctlr1 |= regs.SPI_CTLR1_CPOL | regs.SPI_CTLR1_CPHA,
    }

    if (config.bit_order == .lsb_first) ctlr1 |= regs.SPI_CTLR1_LSBFIRST;

    s.CTLR1 = ctlr1;
    s.CTLR1 |= regs.SPI_CTLR1_SPE; // enable
}

/// 1 バイト送受信（全二重）。送ったバイトと同時に受信したバイトを返す。
pub fn transfer(tx: u8) u8 {
    const s = regs.spi1();
    while ((s.STATR & regs.SPI_STATR_TXE) == 0) {}
    s.DATAR = tx;
    while ((s.STATR & regs.SPI_STATR_RXNE) == 0) {}
    return @intCast(s.DATAR & 0xFF);
}

/// 受信を無視して 1 バイト書くだけ（センサ等への片方向書き込み）。
pub fn write(byte: u8) void {
    _ = transfer(byte);
}

/// ダミーバイトを送って 1 バイト読む。
pub fn read() u8 {
    return transfer(0xFF);
}

/// バッファを丸ごと送受信する。`rx` が与えられれば同じ長さの受信を書き戻す。
pub fn transferBuffer(tx: []const u8, rx: ?[]u8) void {
    for (tx, 0..) |b, i| {
        const got = transfer(b);
        if (rx) |dst| {
            if (i < dst.len) dst[i] = got;
        }
    }
}

/// SPI が転送を完了し、シフトレジスタが空になるまで待つ（CS を上げる前に）。
pub fn flush() void {
    const s = regs.spi1();
    while ((s.STATR & regs.SPI_STATR_TXE) == 0) {}
    while ((s.STATR & regs.SPI_STATR_BSY) != 0) {}
}

/// TX/RX の DMA 要求を有効化する（dma HAL と組み合わせて使う）。
pub fn enableDma(tx_dma: bool, rx_dma: bool) void {
    const s = regs.spi1();
    var ctlr2: u16 = 0;
    if (tx_dma) ctlr2 |= regs.SPI_CTLR2_TXDMAEN;
    if (rx_dma) ctlr2 |= regs.SPI_CTLR2_RXDMAEN;
    s.CTLR2 |= ctlr2;
}

/// DATAR レジスタのアドレス（DMA の周辺アドレスに使う）。
pub fn dataRegisterAddress() u32 {
    return regs.SPI1_BASE + 0x0C;
}
