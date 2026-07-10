//! USART1 TX を DMA で送るサンプル。
//!
//! CPU はメッセージを 1 バイトずつポーリング送信する代わりに、DMA1 ch4 に
//! バッファ転送を丸投げする。転送中も `main` ループは他の仕事（ここでは LED の
//! トグル）を続けられる。
//!
//! 配線:
//!     TX  = PD5  (115200 8N1, USB-シリアル変換へ)
//!     LED = PD0

const fun = @import("ch32fun");

pub export fn _start() noreturn {
    main();
}

const message = "DMA hello from CH32V003\r\n";

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    fun.uart.init(115200);
    fun.uart.enableTxDma();
    fun.dma.init();

    const led = fun.gpio.pin(.D, 0);
    led.configure(.output_pp_10mhz);

    while (true) {
        // DMA ch4 (USART1_TX) にメッセージを渡して送信開始。
        fun.dma.startMemToPeriph(.usart1_tx, .{
            .periph_addr = fun.uart.dataRegisterAddress(),
            .mem = message,
        });

        // 転送が終わるまで LED を点滅させ続ける（CPU は自由）。
        while (!fun.dma.isComplete(.usart1_tx)) {
            led.toggle();
            fun.time.delayMs(20);
        }
        fun.dma.clear(.usart1_tx);
        fun.dma.stop(.usart1_tx);
        fun.uart.flush();

        fun.time.delayMs(1000);
    }
}
