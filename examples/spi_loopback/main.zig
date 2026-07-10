//! SPI1 マスタのループバック確認サンプル。
//!
//! 配線（CH32V003 デフォルトピン）:
//!     SCK  = PC5
//!     MOSI = PC6
//!     MISO = PC7   ← MOSI(PC6) とジャンパで直結するとループバックになる
//!     CS   = PC3   （任意の GPIO）
//!     LED  = PD0
//!
//! MOSI と MISO を直結した状態で 1 バイト送ると、同じ値が読み戻る。
//! 一致すれば LED が点灯、不一致なら速く点滅する。

const fun = @import("ch32fun");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    // SPI ピンをオルタネート機能でセットアップ。
    fun.gpio.pin(.C, 5).configure(.output_af_pp_30mhz); // SCK
    fun.gpio.pin(.C, 6).configure(.output_af_pp_30mhz); // MOSI
    fun.gpio.pin(.C, 7).configure(.input_pull); // MISO

    const cs = fun.gpio.pin(.C, 3);
    cs.configure(.output_pp_10mhz);
    cs.write(true); // deselect (active-low)

    const led = fun.gpio.pin(.D, 0);
    led.configure(.output_pp_10mhz);

    fun.spi.init(.{ .baud = .div16, .mode = .mode0 });

    var pattern: u8 = 0x5A;
    while (true) : (pattern +%= 1) {
        cs.write(false);
        const echoed = fun.spi.transfer(pattern);
        fun.spi.flush();
        cs.write(true);

        if (echoed == pattern) {
            led.write(true);
            fun.time.delayMs(200);
        } else {
            // ループバック不一致: 速く点滅して知らせる。
            var i: u8 = 0;
            while (i < 6) : (i += 1) {
                led.toggle();
                fun.time.delayMs(60);
            }
        }
    }
}
