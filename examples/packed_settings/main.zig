//! packed_settings
//!
//! Zig の `packed struct(uN)` で、 設定一式をビット幅指定付きで定義する。
//! `@bitCast(u32, settings)` で 4 バイトのスカラに、 逆方向もキャスト 1 回。
//! それをそのまま Flash Slot に保存することで、 「設定全部 = u32 1 ワード」の
//! コンパクトな永続化が実現する。
//!
//! 動作:
//!   - 起動時に Flash から settings を読む。 magic 不一致なら初期値
//!   - ボタン (PD1) を押すたびに mode を 1 つ進める
//!   - mode に応じて LED (PD0) の点滅パターンが変わる
//!   - 設定が変わったときだけ Flash に保存 (寿命対策)
//!
//! 配線: LED PD0、 ボタン PD1 (内部プルアップ)

const std = @import("std");
const fun = @import("ch32fun");

// -------- packed struct で 32-bit にきっかり収まる設定 -------------------

const LedMode = enum(u3) {
    off = 0,
    solid = 1,
    slow_blink = 2,
    fast_blink = 3,
    sos = 4,
    _, // 残りを許容
};

const Settings = packed struct(u32) {
    mode: LedMode, // 3 bit
    brightness: u4, // 4 bit (今回はLEDなので未使用デモ)
    buzzer: bool, // 1 bit
    volume: u4, // 4 bit
    save_count: u12, // 12 bit (寿命確認用カウンタ)
    revision: u8, // 8 bit (互換性管理)
};

comptime {
    if (@sizeOf(Settings) != 4) @compileError("Settings must fit in u32");
}

const initial: Settings = .{
    .mode = .slow_blink,
    .brightness = 8,
    .buzzer = true,
    .volume = 4,
    .save_count = 0,
    .revision = 1,
};

// Slot.default(1) は USER_DATA の物理アドレス (extern var) を runtime に取得するので、
// コンテナレベル const にはせず、 必要時に取り出す。
fn settingsSlot() fun.flash.Slot(Settings) {
    return fun.flash.Slot(Settings).default(1);
}

fn loadSettings() Settings {
    return settingsSlot().load() orelse initial;
}

fn saveSettings(s: Settings) void {
    settingsSlot().save(s) catch {};
}

// -------- LED パターン -------------------------------------------------

const Pin = @TypeOf(fun.gpio.pin(.D, 0));

fn applyPattern(led: Pin, mode: LedMode, tick: u32) void {
    switch (mode) {
        .off => led.write(false),
        .solid => led.write(true),
        .slow_blink => led.write((tick / 30) % 2 == 0),
        .fast_blink => led.write((tick / 5) % 2 == 0),
        .sos => {
            // ... --- ... を 28 単位で表現 (1 単位 ≒ 60ms)
            const t = tick % 28;
            const on = switch (t) {
                0, 2, 4, 8, 9, 10, 12, 13, 14, 16, 17, 18, 20, 22, 24 => true,
                else => false,
            };
            led.write(on);
        },
        _ => led.write(false),
    }
}

fn nextMode(m: LedMode) LedMode {
    return switch (m) {
        .off => .solid,
        .solid => .slow_blink,
        .slow_blink => .fast_blink,
        .fast_blink => .sos,
        .sos => .off,
        _ => .off,
    };
}

// -------- main ---------------------------------------------------------

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();
    fun.input.initButtonPd1Pullup();

    const led = fun.gpio.pin(.D, 0);
    led.configure(.output_pp_10mhz);

    var s = loadSettings();

    // u32 と struct の相互変換を試すデモ (実機では行わなくて良いが、 教材として)
    const raw: u32 = @bitCast(s);
    const round_trip: Settings = @bitCast(raw);
    _ = round_trip; // 確認用

    var prev_btn = false;
    var tick: u32 = 0;
    var dirty = false;
    var debounce: u8 = 0;

    while (true) : (tick +%= 1) {
        const now = fun.input.isButtonPressed();
        if (now and !prev_btn and debounce == 0) {
            s.mode = nextMode(s.mode);
            // 寿命カウンタを進める
            s.save_count +%= 1;
            dirty = true;
            debounce = 30; // 約 600ms の入力無視
        }
        prev_btn = now;
        if (debounce > 0) debounce -= 1;

        // 一定時間ボタン操作が止んだら Flash に保存
        if (dirty and debounce == 0) {
            saveSettings(s);
            dirty = false;
        }

        applyPattern(led, s.mode, tick);
        fun.time.delayMs(20);
    }
}
