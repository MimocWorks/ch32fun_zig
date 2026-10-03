const app = @import("app");

pub const ch32fun_ssd1306_basic_ascii_font = if (@hasDecl(app, "ch32fun_ssd1306_basic_ascii_font"))
    app.ch32fun_ssd1306_basic_ascii_font
else
    false;
pub const ch32fun_ssd1306_buffer_mode = if (@hasDecl(app, "ch32fun_ssd1306_buffer_mode"))
    app.ch32fun_ssd1306_buffer_mode
else
    .full;
pub const ch32fun_ssd1306_panel_size = if (@hasDecl(app, "ch32fun_ssd1306_panel_size"))
    app.ch32fun_ssd1306_panel_size
else
    .@"128x64";
pub const ch32fun_swio_log_enabled = if (@hasDecl(app, "ch32fun_swio_log_enabled"))
    app.ch32fun_swio_log_enabled
else
    @import("builtin").mode == .debug;

const startup = @import("runtime/startup_exti.zig");
comptime {
    _ = &startup._start;
}

pub fn main() noreturn {
    app.main();
    while (true) asm volatile ("wfi");
}
