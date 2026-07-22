//! レジスタを直接操作して PD0 の LED を点滅させる最小例。
//!
//! HAL の gpio/time API は使わず、RCC / GPIOD / SysTick の MMIO レジスタを
//! volatile pointer で直接読み書きする。
//!
//! 配線: LED アノード -> 抵抗 -> PD0、カソード -> GND。

const fun = @import("ch32fun");

const APB2PERIPH_BASE: usize = 0x4001_0000;
const AHBPERIPH_BASE: usize = 0x4002_0000;
const CORE_PERIPH_BASE: usize = 0xE000_0000;

const RCC_BASE: usize = AHBPERIPH_BASE + 0x1000;
const GPIOD_BASE: usize = APB2PERIPH_BASE + 0x1400;
const SYSTICK_BASE: usize = CORE_PERIPH_BASE + 0xF000;

const RCC_APB2_GPIOD: u32 = 0x0000_0020;
const LED_PIN: u5 = 0;
const LED_MODE_OUTPUT_PP_10MHZ: u32 = 0x1;

const RccRegs = extern struct {
    CTLR: u32,
    CFGR0: u32,
    INTR: u32,
    APB2PRSTR: u32,
    APB1PRSTR: u32,
    AHBPCENR: u32,
    APB2PCENR: u32,
    APB1PCENR: u32,
    RESERVED0: u32,
    RSTSCKR: u32,
};

const GpioRegs = extern struct {
    CFGLR: u32,
    CFGHR: u32,
    INDR: u32,
    OUTDR: u32,
    BSHR: u32,
    BCR: u32,
    LCKR: u32,
};

const SysTickRegs = extern struct {
    CTLR: u32,
    SR: u32,
    CNT: u32,
    RESERVED0: u32,
    CMP: u32,
    RESERVED1: u32,
};

fn rcc() *volatile RccRegs {
    return @ptrFromInt(RCC_BASE);
}

fn gpioD() *volatile GpioRegs {
    return @ptrFromInt(GPIOD_BASE);
}

fn systick() *volatile SysTickRegs {
    return @ptrFromInt(SYSTICK_BASE);
}

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});

    rcc().APB2PCENR |= RCC_APB2_GPIOD;

    const mode_shift: u5 = LED_PIN * 4;
    const mode_mask: u32 = @as(u32, 0xF) << mode_shift;
    gpioD().CFGLR = (gpioD().CFGLR & ~mode_mask) | (LED_MODE_OUTPUT_PP_10MHZ << mode_shift);

    while (true) {
        gpioD().BSHR = @as(u32, 1) << LED_PIN;
        delayMs(250);
        gpioD().BSHR = (@as(u32, 1) << LED_PIN) << 16;
        delayMs(250);
    }
}

fn delayMs(ms: u32) void {
    const ticks_per_ms: u32 = fun.system.core_clock_hz / 1000;
    const wait_ticks = ms * ticks_per_ms;
    const start = systick().CNT;
    while (@as(u32, systick().CNT -% start) < wait_ticks) {}
}
