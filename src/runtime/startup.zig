const root = @import("root");
const regs = @import("../periph/registers.zig");
const time = @import("../hal/time.zig");
const exti = @import("../hal/exti.zig");

extern var _sbss: u32;
extern var _ebss: u32;
extern var _sdata: u32;
extern var _edata: u32;
extern var _sidata: u32;
extern var _stack_top: u32;

pub export fn _start() callconv(.naked) noreturn {
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

    asm volatile ("li t0, 0x03; csrw 0x804, t0" ::: .{ .t0 = true });
    asm volatile ("csrs mstatus, %[bits]"
        :
        : [bits] "r" (@as(u32, 0x88)),
        : .{ .memory = true });
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
        \\addi sp, sp, -128
        \\sw ra, 124(sp)
        \\sw gp, 120(sp)
        \\sw tp, 116(sp)
        \\sw t0, 112(sp)
        \\sw t1, 108(sp)
        \\sw t2, 104(sp)
        \\sw s0, 100(sp)
        \\sw s1, 96(sp)
        \\sw a0, 92(sp)
        \\sw a1, 88(sp)
        \\sw a2, 84(sp)
        \\sw a3, 80(sp)
        \\sw a4, 76(sp)
        \\sw a5, 72(sp)
        \\sw a6, 68(sp)
        \\sw a7, 64(sp)
        \\sw s2, 60(sp)
        \\sw s3, 56(sp)
        \\sw s4, 52(sp)
        \\sw s5, 48(sp)
        \\sw s6, 44(sp)
        \\sw s7, 40(sp)
        \\sw s8, 36(sp)
        \\sw s9, 32(sp)
        \\sw s10, 28(sp)
        \\sw s11, 24(sp)
        \\sw t3, 20(sp)
        \\sw t4, 16(sp)
        \\sw t5, 12(sp)
        \\sw t6, 8(sp)
        \\call _systick_irq_body
        \\lw ra, 124(sp)
        \\lw gp, 120(sp)
        \\lw tp, 116(sp)
        \\lw t0, 112(sp)
        \\lw t1, 108(sp)
        \\lw t2, 104(sp)
        \\lw s0, 100(sp)
        \\lw s1, 96(sp)
        \\lw a0, 92(sp)
        \\lw a1, 88(sp)
        \\lw a2, 84(sp)
        \\lw a3, 80(sp)
        \\lw a4, 76(sp)
        \\lw a5, 72(sp)
        \\lw a6, 68(sp)
        \\lw a7, 64(sp)
        \\lw s2, 60(sp)
        \\lw s3, 56(sp)
        \\lw s4, 52(sp)
        \\lw s5, 48(sp)
        \\lw s6, 44(sp)
        \\lw s7, 40(sp)
        \\lw s8, 36(sp)
        \\lw s9, 32(sp)
        \\lw s10, 28(sp)
        \\lw s11, 24(sp)
        \\lw t3, 20(sp)
        \\lw t4, 16(sp)
        \\lw t5, 12(sp)
        \\lw t6, 8(sp)
        \\addi sp, sp, 128
        \\mret
    );
}

export fn _systick_irq_body() callconv(.c) void {
    time.systickInterruptBody();
}

pub export fn _exti7_0_irq_entry() callconv(.naked) void {
    asm volatile (
        \\addi sp, sp, -128
        \\sw ra, 124(sp)
        \\sw gp, 120(sp)
        \\sw tp, 116(sp)
        \\sw t0, 112(sp)
        \\sw t1, 108(sp)
        \\sw t2, 104(sp)
        \\sw s0, 100(sp)
        \\sw s1, 96(sp)
        \\sw a0, 92(sp)
        \\sw a1, 88(sp)
        \\sw a2, 84(sp)
        \\sw a3, 80(sp)
        \\sw a4, 76(sp)
        \\sw a5, 72(sp)
        \\sw a6, 68(sp)
        \\sw a7, 64(sp)
        \\sw s2, 60(sp)
        \\sw s3, 56(sp)
        \\sw s4, 52(sp)
        \\sw s5, 48(sp)
        \\sw s6, 44(sp)
        \\sw s7, 40(sp)
        \\sw s8, 36(sp)
        \\sw s9, 32(sp)
        \\sw s10, 28(sp)
        \\sw s11, 24(sp)
        \\sw t3, 20(sp)
        \\sw t4, 16(sp)
        \\sw t5, 12(sp)
        \\sw t6, 8(sp)
        \\call _exti7_0_irq_body
        \\lw ra, 124(sp)
        \\lw gp, 120(sp)
        \\lw tp, 116(sp)
        \\lw t0, 112(sp)
        \\lw t1, 108(sp)
        \\lw t2, 104(sp)
        \\lw s0, 100(sp)
        \\lw s1, 96(sp)
        \\lw a0, 92(sp)
        \\lw a1, 88(sp)
        \\lw a2, 84(sp)
        \\lw a3, 80(sp)
        \\lw a4, 76(sp)
        \\lw a5, 72(sp)
        \\lw a6, 68(sp)
        \\lw a7, 64(sp)
        \\lw s2, 60(sp)
        \\lw s3, 56(sp)
        \\lw s4, 52(sp)
        \\lw s5, 48(sp)
        \\lw s6, 44(sp)
        \\lw s7, 40(sp)
        \\lw s8, 36(sp)
        \\lw s9, 32(sp)
        \\lw s10, 28(sp)
        \\lw s11, 24(sp)
        \\lw t3, 20(sp)
        \\lw t4, 16(sp)
        \\lw t5, 12(sp)
        \\lw t6, 8(sp)
        \\addi sp, sp, 128
        \\mret
    );
}

export fn _exti7_0_irq_body() callconv(.c) void {
    exti.handleInterrupt();
}

fn makeVectorTable() [39]?*const anyopaque {
    var table = [_]?*const anyopaque{null} ** 39;
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
