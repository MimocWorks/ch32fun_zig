//! USART1 (PD5, 8N1 115200bps) で "hello" を 1 秒ごとに送出する。
//! 受信側は PC の USB-シリアル変換 (CP2102 等) を PD5 ↔ TXD 反転、 GND ↔ GND で接続。
//! 端末は 115200bps で開く。

const fun = @import("ch32fun");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.log.init(115200);

    var n: u32 = 0;
    while (true) : (n +%= 1) {
        fun.log.info("hello from CH32V003! tick={d}", .{n});
        fun.time.delayMs(1000);
    }
}
