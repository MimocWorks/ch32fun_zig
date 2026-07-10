//! PD1 ボタンを EXTI 立ち下がりで割り込み駆動し、 LED (PD0) をトグルする。
//! 配線: ボタン → PD1 と GND の間。 LED は PD0。 (内部プルアップを使う)

const fun = @import("ch32fun");

var press_count: u32 = 0;

fn onButtonPress(line: u8) callconv(.c) void {
    _ = line;
    press_count +%= 1;
    fun.gpio.pin(.D, 0).toggle();
}

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    fun.gpio.pin(.D, 0).configure(.output_pp_10mhz);
    fun.input.initButtonPd1Pullup();

    fun.exti.config(.{
        .port = .D,
        .line = 1,
        .trigger = .falling,
        .handler = onButtonPress,
    });
    fun.exti.enable(1);
    fun.system.enableInterrupts();

    while (true) {
        fun.system.wfi();
    }
}
