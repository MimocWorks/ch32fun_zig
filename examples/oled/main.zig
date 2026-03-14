const fun = @import("ch32fun");
const assets = @import("assets.zig");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.time.systick.init(1000);
    fun.input.initButtonPd1Pullup();

    fun.ssd1306.initI2c() catch unreachable;
    fun.ssd1306.initPanel() catch unreachable;

    var x: i16 = 0;
    var dx: i16 = 1;
    var fast_mode = false;
    var prev_button = false;
    var frame: u8 = 0;

    while (true) {
        const pressed = fun.input.isButtonPressed();
        if (pressed and !prev_button) {
            fast_mode = !fast_mode;
        }
        prev_button = pressed;

        fun.ssd1306.setbuf(false);
        fun.ssd1306.drawRect(0, 0, 128, 64, true);

        const title = fun.ssd1306.measureText("OLED+", .x1);
        const title_x = @divTrunc(@as(i16, fun.ssd1306.width) - title.w, 2);
        fun.ssd1306.fillRoundRect(title_x - 4, 2, title.w + 8, 12, 4, true);
        fun.ssd1306.drawStrSz(title_x, 4, "OLED+", false, .x1);
        fun.ssd1306.drawStrSz(92, 4, if (fast_mode) "FAST" else "SLOW", true, .x1);

        fun.ssd1306.drawRoundRect(4, 16, 30, 20, 5, true);
        fun.ssd1306.fillCircle(19, 26, 6, (frame & 0x04) != 0);
        fun.ssd1306.drawLine(38, 18, 58, 34, true);
        fun.ssd1306.drawLine(38, 34, 58, 18, true);
        fun.ssd1306.drawCircle(72, 26, 8, true);
        fun.ssd1306.fillRect(86, 18, 18, 16, true);
        fun.ssd1306.drawBitmapMasked(91, 22, &assets.masked_icon, &assets.masked_icon_mask, 8, 8, .normal, .deg0);
        fun.ssd1306.drawRoundRect(108, 18, 16, 16, 4, true);
        fun.ssd1306.drawBitmapMasked(112, 22, &assets.masked_icon, &assets.masked_icon_mask, 8, 8, .invert, .deg90);

        const text_rotation: fun.ssd1306.Rotation = switch ((frame / 16) & 0x03) {
            0 => .deg0,
            1 => .deg90,
            2 => .deg180,
            else => .deg270,
        };
        const label = fun.ssd1306.measureTextRot("ROT", .x1, text_rotation);
        const label_x = 6 + @divTrunc(18 - label.w, 2);
        const label_y = 40 + @divTrunc(18 - label.h, 2);
        fun.ssd1306.drawRoundRect(4, 38, 22, 22, 4, true);
        fun.ssd1306.drawStrRot(label_x, label_y, "ROT", true, .x1, text_rotation, false);

        fun.ssd1306.drawImageRot(x, 44, &assets.sprite_demo, 8, 8, .normal, .deg0);
        fun.ssd1306.drawImageRot(32, 44, &assets.sprite_demo, 8, 8, .normal, .deg90);
        fun.ssd1306.drawImageRot(48, 44, &assets.sprite_demo, 8, 8, .normal, .deg180);
        fun.ssd1306.drawImageRot(64, 44, &assets.sprite_demo, 8, 8, .normal, .deg270);
        fun.ssd1306.drawBitmapMasked(84, 44, &assets.masked_icon, &assets.masked_icon_mask, 8, 8, .normal, .deg180);
        fun.ssd1306.refresh() catch unreachable;

        x += dx;
        if (x <= 0) dx = 1;
        if (x >= 120) dx = -1; // 128 - sprite width (8)
        frame +%= 1;

        fun.time.delayMs(if (fast_mode) 12 else 35);
    }
}
