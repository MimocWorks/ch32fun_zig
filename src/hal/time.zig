const regs = @import("../periph/registers.zig");
const system = @import("../system/system.zig");

var systick_ticks: u32 = 0;
var systick_ticks_per_irq: u32 = 0;
var tick_handler: ?*const fn () callconv(.c) void = null;

pub fn delayMs(ms: u32) void {
    const ticks_per_ms = system.core_clock_hz / 1000;
    const wait_ticks = ms * ticks_per_ms;
    const start = regs.systick().CNT;

    while (@as(u32, regs.systick().CNT -% start) < wait_ticks) {}
}

pub fn delayUs(us: u32) void {
    const wait_ticks = usToCycles(us);
    const start = nowCycles();

    while (@as(u32, nowCycles() -% start) < wait_ticks) {}
}

pub fn nowCycles() u32 {
    return regs.systick().CNT;
}

pub fn elapsedUsSince(start_cycles: u32) u32 {
    return cyclesToUs(@as(u32, nowCycles() -% start_cycles));
}

pub fn usToCycles(us: u32) u32 {
    const ticks_per_us = system.core_clock_hz / 1_000_000;
    return @intCast(@as(u64, us) * @as(u64, ticks_per_us));
}

pub fn cyclesToUs(cycles: u32) u32 {
    const ticks_per_us = system.core_clock_hz / 1_000_000;
    if (ticks_per_us == 0) return 0;
    return cycles / ticks_per_us;
}

pub const systick = struct {
    pub fn init(tick_hz: u32) void {
        const st = regs.systick();

        systick_ticks_per_irq = system.core_clock_hz / tick_hz;
        if (systick_ticks_per_irq == 0) {
            systick_ticks_per_irq = 1;
        }

        st.CTLR = 0;
        st.CMP = systick_ticks_per_irq - 1;
        st.CNT = 0;
        st.SR = 0;
        systick_ticks = 0;

        // Keep SysTick running from HCLK without ISR binding in this stage.
        st.CTLR = regs.SYSTICK_CTLR_STE | regs.SYSTICK_CTLR_STCLK;
    }

    pub fn nowTicks() u64 {
        const st = regs.systick();
        if (systick_ticks_per_irq == 0) return 0;
        return st.CNT / systick_ticks_per_irq;
    }

    pub fn onTick(handler: *const fn () callconv(.c) void) void {
        tick_handler = handler;
    }
};

pub fn systickInterruptBody() callconv(.c) void {
    const st = regs.systick();

    st.CMP +%= systick_ticks_per_irq;
    st.SR = 0;
    systick_ticks +%= 1;

    if (tick_handler) |handler| {
        handler();
    }
}
