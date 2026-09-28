const fun = @import("ch32fun");
const ui = @import("mimoc_ui");

/// Transfer one frozen presentation snapshot through the HAL's own 128-byte
/// page buffer. Call runtime.update() before entering this function.
pub fn draw(runtime: anytype) !void {
    fun.ssd1306.firstPage();
    var page: u8 = 0;
    while (true) {
        try ui.headless.renderPage(runtime, fun.ssd1306.buffer[0..], 128, page);
        if (!(try fun.ssd1306.nextPage())) break;
        page += 1;
    }
}
