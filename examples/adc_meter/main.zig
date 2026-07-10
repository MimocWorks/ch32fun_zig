//! ADC でアナログ電圧を読み、 値を UART に出力。
//! 配線: 可変抵抗 (3.3V — POT — GND)、 中点を PD2 (= ADC ch3) に。

const fun = @import("ch32fun");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();
    fun.log.init(115200);

    fun.gpio.pin(.D, 2).configure(.input_analog); // ch3
    fun.adc.init();

    while (true) {
        const raw = fun.adc.readAveraged(3, 8);
        // raw を 0..3300 mV に変換 (10-bit 0..1023, Vref=3.3V 想定)
        const mv: u32 = (@as(u32, raw) * 3300) / 1023;
        fun.log.info("ADC ch3 raw={d} ~{d}mV", .{ raw, mv });
        fun.time.delayMs(200);
    }
}
