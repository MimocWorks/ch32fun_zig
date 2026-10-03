const root = @import("root");
const fun = @import("ch32fun");
const regs = fun.registers;
const time = fun.time;
const exti = fun.exti;

extern var _sbss: u32;
extern var _ebss: u32;
extern var _sdata: u32;
extern var _edata: u32;
extern var _sidata: u32;
extern var _stack_top: u32;

pub export fn _start() linksection(".reset_entry") callconv(.naked) noreturn {
    asm volatile (
        \\.option push
        \\.option norelax
        \\la gp, __global_pointer$
        \\.option pop
        \\la sp, _stack_top
        \\j _start_c
    );
}

export fn _start_c() callconv(.c) noreturn {
    zeroBss();
    copyData();

    setupMachineState();

    // Start free-running SysTick (HCLK source) for delay API.
    regs.systick().CTLR = regs.SYSTICK_CTLR_STE | regs.SYSTICK_CTLR_STCLK;

    root.main();
}

fn zeroBss() void {
    var p: [*]volatile u32 = @ptrCast(&_sbss);
    const end: [*]volatile u32 = @ptrCast(&_ebss);
    while (@intFromPtr(p) < @intFromPtr(end)) : (p += 1) {
        p[0] = 0;
    }
}

fn copyData() void {
    var src: [*]const u32 = @ptrCast(&_sidata);
    var dst: [*]volatile u32 = @ptrCast(&_sdata);
    const end: [*]volatile u32 = @ptrCast(&_edata);
    while (@intFromPtr(dst) < @intFromPtr(end)) : ({
        src += 1;
        dst += 1;
    }) {
        dst[0] = src[0];
    }
}

fn setupMachineState() void {
    const mtvec_addr: usize = @intFromPtr(&vector_table) | 0x3;

    // Use the regular software-stacked interrupt ABI. QingKe HPE changes the
    // ABI and cannot be enabled for these naked entries.
    asm volatile ("csrw 0x804, zero" ::: .{ .memory = true });
    // MPP=Machine, MPIE=1 and MIE=0, matching WCH's non-HPE startup. Firmware
    // enables MIE only after its peripherals and PFIC lines are configured.
    asm volatile ("li t0, 0x1880; csrw mstatus, t0" ::: .{ .t0 = true, .memory = true });
    asm volatile ("csrw mtvec, %[vec]"
        :
        : [vec] "r" (@as(u32, @truncate(mtvec_addr))),
        : .{ .memory = true });
}

fn defaultInterruptBody() callconv(.c) void {
    while (true) {
        asm volatile ("wfi");
    }
}

pub export fn _default_irq_entry() callconv(.naked) void {
    asm volatile (
        \\j _default_irq_body
    );
}

export fn _default_irq_body() callconv(.c) noreturn {
    defaultInterruptBody();
    unreachable;
}

pub export fn _systick_irq_entry() callconv(.naked) void {
    asm volatile (
        \\addi sp, sp, -64
        \\sw ra, 60(sp)
        \\sw gp, 56(sp)
        \\sw tp, 52(sp)
        \\sw t0, 48(sp)
        \\sw t1, 44(sp)
        \\sw t2, 40(sp)
        \\sw s0, 36(sp)
        \\sw s1, 32(sp)
        \\sw a0, 28(sp)
        \\sw a1, 24(sp)
        \\sw a2, 20(sp)
        \\sw a3, 16(sp)
        \\sw a4, 12(sp)
        \\sw a5, 8(sp)
        \\call _systick_irq_body
        \\lw ra, 60(sp)
        \\lw gp, 56(sp)
        \\lw tp, 52(sp)
        \\lw t0, 48(sp)
        \\lw t1, 44(sp)
        \\lw t2, 40(sp)
        \\lw s0, 36(sp)
        \\lw s1, 32(sp)
        \\lw a0, 28(sp)
        \\lw a1, 24(sp)
        \\lw a2, 20(sp)
        \\lw a3, 16(sp)
        \\lw a4, 12(sp)
        \\lw a5, 8(sp)
        \\addi sp, sp, 64
        \\mret
    );
}

export fn _systick_irq_body() callconv(.c) void {
    time.systickInterruptBody();
}

pub export fn _exti7_0_irq_entry() callconv(.naked) void {
    asm volatile (
        \\addi sp, sp, -64
        \\sw ra, 60(sp)
        \\sw gp, 56(sp)
        \\sw tp, 52(sp)
        \\sw t0, 48(sp)
        \\sw t1, 44(sp)
        \\sw t2, 40(sp)
        \\sw s0, 36(sp)
        \\sw s1, 32(sp)
        \\sw a0, 28(sp)
        \\sw a1, 24(sp)
        \\sw a2, 20(sp)
        \\sw a3, 16(sp)
        \\sw a4, 12(sp)
        \\sw a5, 8(sp)
        \\call _exti7_0_irq_body
        \\lw ra, 60(sp)
        \\lw gp, 56(sp)
        \\lw tp, 52(sp)
        \\lw t0, 48(sp)
        \\lw t1, 44(sp)
        \\lw t2, 40(sp)
        \\lw s0, 36(sp)
        \\lw s1, 32(sp)
        \\lw a0, 28(sp)
        \\lw a1, 24(sp)
        \\lw a2, 20(sp)
        \\lw a3, 16(sp)
        \\lw a4, 12(sp)
        \\lw a5, 8(sp)
        \\addi sp, sp, 64
        \\mret
    );
}

export fn _exti7_0_irq_body() callconv(.c) void {
    exti.handleInterrupt();
}

fn makeVectorTable() [39]?*const anyopaque {
    var table: [39]?*const anyopaque = @splat(null);
    table[2] = &_default_irq_entry; // NMI
    table[3] = &_default_irq_entry; // Exception
    table[12] = &_systick_irq_entry; // SysTick
    table[14] = &_default_irq_entry; // Software

    var i: usize = 16;
    while (i < table.len) : (i += 1) {
        table[i] = &_default_irq_entry;
    }

    // 個別 IRQ 番号 = table[16 + IRQn]
    table[16 + 20] = &_exti7_0_irq_entry; // EXTI7_0_IRQn

    return table;
}

pub export const vector_table linksection(".vector_table") = makeVectorTable();
