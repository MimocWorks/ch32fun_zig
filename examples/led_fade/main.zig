//! TIM1_CH1 (PD2) で LED の明るさをゆっくり呼吸させる。
//! 配線: LED アノード → 抵抗 → PD2、 カソード → GND。

const fun = @import("ch32fun");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    // PD2 を Alternate Function Push-Pull (TIM1_CH1) に
    fun.gpio.pin(.D, 2).configure(.output_af_pp_10mhz);

    // 48MHz / 48 = 1MHz カウント、 period 1000 = 1kHz PWM
    fun.pwm.tim1.init(.{ .prescaler = 47, .period = 1000 });
    fun.pwm.tim1.enableChannel(.ch1);

    var duty: i16 = 0;
    var step: i16 = 8;
    while (true) {
        fun.pwm.tim1.setDuty(.ch1, @intCast(duty));
        duty += step;
        if (duty >= 1000) {
            duty = 1000;
            step = -step;
        } else if (duty <= 0) {
            duty = 0;
            step = -step;
        }
        fun.time.delayMs(15);
    }
}
