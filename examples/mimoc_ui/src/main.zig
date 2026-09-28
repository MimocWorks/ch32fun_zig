const fun = @import("ch32fun");
const ui = @import("mimoc_ui");
const options = @import("build_options");
const adapter = @import("adapter.zig");

pub const ch32fun_ssd1306_buffer_mode = .page;
pub const ch32fun_swio_log_enabled = false;

const Ui = ui.runtime.Runtime(.{ .max_nodes = options.max_nodes, .max_animations = options.max_animations });
var runtime: Ui = .{};

fn rebuild() void {
    var view = runtime.beginView();
    view.begin(0, .stack, 0, 0, .start) catch unreachable;
    view.begin(1, .column, 2, 1, .start) catch unreachable;
    view.add(.{ .id = 2, .kind = .text, .text = "MO-BUS" }) catch unreachable;
    view.add(.{ .id = 3, .kind = .divider, .min_size = .{ .w = 124, .h = 1 } }) catch unreachable;
    view.add(.{ .id = 10, .kind = .button, .text = "CHAT", .min_size = .{ .w = 124, .h = 12 } }) catch unreachable;
    view.add(.{ .id = 11, .kind = .button, .text = "CQ", .min_size = .{ .w = 124, .h = 12 } }) catch unreachable;
    view.add(.{ .id = 12, .kind = .button, .text = "EHAGAKI", .min_size = .{ .w = 124, .h = 12 } }) catch unreachable;
    view.end();
    const indicator_y: i16 = switch (runtime.focused_id orelse 10) { 11 => 25, 12 => 38, else => 12 };
    view.add(.{ .id = 30, .kind = .filled_rect, .min_size = .{ .w = 2, .h = 10 }, .offset = .{ .y = indicator_y }, .animation = ui.animation.Animation.easeOut(180) }) catch unreachable;
    view.end();
    runtime.finishView(&view) catch unreachable;
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.time.systick.init(1000);
    fun.input.initButtonPd1Pullup();
    fun.ssd1306.initI2c() catch unreachable;
    fun.ssd1306.initPanel() catch unreachable;

    var now_ms: u32 = 0;
    var last_cycles = fun.time.nowCycles();
    var previous_pressed = false;
    runtime.update(now_ms);
    rebuild();

    while (true) {
        const current_cycles = fun.time.nowCycles();
        const elapsed_cycles = current_cycles -% last_cycles;
        last_cycles = current_cycles;
        now_ms +%= elapsed_cycles / (fun.system.core_clock_hz / 1000);
        runtime.update(now_ms);

        const pressed = fun.input.isButtonPressed();
        if (pressed and !previous_pressed) {
            _ = runtime.action(.down);
            rebuild();
        }
        previous_pressed = pressed;

        adapter.draw(&runtime) catch unreachable;
        fun.time.delayMs(10);
    }
}
