//! state_machine_game
//!
//! tagged union + 網羅 switch でゲームの 3 ステートを表現する。
//! Zig の union(enum) は **網羅性チェック付き switch** と相性が良く、
//! 「新しいステートを追加した瞬間にハンドラ抜けが compile error になる」 性質を
//! 持つ。 これは組み込みのステートマシン記述において、 とりわけ嬉しい。
//!
//! ゲーム本体: 横バーが左→右に往復する。 スイートスポット (画面中央付近)
//! でボタン (PD1) を押せたら +1 点、 3 ミス で GAME OVER。
//!
//! 配線:
//!   OLED SDA → PC1, OLED SCL → PC2
//!   ボタン PD1 ↔ GND (内部プルアップ利用)
//! Tone (PD4, TIM2_CH1) があれば成功/失敗音が鳴る。 無くても動作する。

const std = @import("std");
const fun = @import("ch32fun");

// -------- ステート (tagged union) --------------------------------------

const Menu = struct {
    blink: u8 = 0,
};

const Playing = struct {
    score: u16 = 0,
    misses: u8 = 0,
    bar_x: i16 = 0,
    bar_dx: i16 = 2,
};

const GameOver = struct {
    final_score: u16,
    blink: u8 = 0,
};

const State = union(enum) {
    menu: Menu,
    playing: Playing,
    game_over: GameOver,
};

const sweet_left: i16 = 56;
const sweet_right: i16 = 72;
const bar_w: i16 = 6;
const bar_y: i16 = 36;
const miss_limit: u8 = 3;

// -------- IO ヘルパ ----------------------------------------------------

fn waitFrame() void {
    fun.time.delayMs(16); // ~60fps
}

fn buttonEdge(prev: *bool) bool {
    const now = fun.input.isButtonPressed();
    const edge = now and !prev.*;
    prev.* = now;
    return edge;
}

fn beep(freq: u32, ms: u32) void {
    // Tone は失敗しても致命傷でないので、 ピン未接続を許容する設計に
    fun.tone.play(freq, ms);
}

fn drawCommon(title: []const u8) void {
    fun.ssd1306.setbuf(false);
    fun.ssd1306.drawRect(0, 0, 128, 64, true);
    fun.ssd1306.drawStrSz(4, 4, title, true, .x1);
}

// -------- 各ステートの描画と更新 ---------------------------------------

fn renderMenu(m: *Menu) void {
    drawCommon("STATE GAME");
    fun.ssd1306.drawStrSz(8, 24, "PRESS BUTTON", true, .x1);
    if ((m.blink / 16) % 2 == 0) {
        fun.ssd1306.drawStrSz(8, 40, "TO START", true, .x1);
    }
    m.blink +%= 1;
}

fn renderPlaying(p: *Playing) void {
    drawCommon("PLAYING");

    // スコアとミス
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "SCORE:{d}", .{p.score}) catch buf[0..0];
    fun.ssd1306.drawStrSz(70, 4, s, true, .x1);
    const m = std.fmt.bufPrint(&buf, "MISS:{d}/{d}", .{ p.misses, miss_limit }) catch buf[0..0];
    fun.ssd1306.drawStrSz(8, 18, m, true, .x1);

    // スイートスポット (帯)
    fun.ssd1306.drawRect(sweet_left, bar_y - 4, sweet_right - sweet_left, 14, true);

    // 動くバー
    fun.ssd1306.fillRect(p.bar_x, bar_y, bar_w, 6, true);
}

fn renderGameOver(g: *GameOver) void {
    drawCommon("GAME OVER");
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "SCORE {d}", .{g.final_score}) catch buf[0..0];
    fun.ssd1306.drawStrSz(36, 24, s, true, .x1);
    if ((g.blink / 16) % 2 == 0) {
        fun.ssd1306.drawStrSz(8, 44, "PRESS TO RESET", true, .x1);
    }
    g.blink +%= 1;
}

/// 1 フレーム分の更新。 ボタンエッジの有無を受け取り、 必要なら別ステートを返す。
fn step(state: *State, btn_pressed: bool) ?State {
    switch (state.*) {
        .menu => |*m| {
            _ = m;
            if (btn_pressed) {
                return State{ .playing = .{} };
            }
            return null;
        },
        .playing => |*p| {
            // バーを動かす
            p.bar_x += p.bar_dx;
            if (p.bar_x <= 0 or p.bar_x + bar_w >= 128) p.bar_dx = -p.bar_dx;

            if (btn_pressed) {
                const bar_center = p.bar_x + @divTrunc(bar_w, 2);
                const in_sweet = bar_center >= sweet_left and bar_center <= sweet_right;
                if (in_sweet) {
                    p.score +|= 1; // 飽和加算 (u16 overflow 防止)
                    beep(880, 60);
                } else {
                    p.misses += 1;
                    beep(220, 120);
                    if (p.misses >= miss_limit) {
                        return State{ .game_over = .{ .final_score = p.score } };
                    }
                }
            }
            return null;
        },
        .game_over => |*g| {
            _ = g;
            if (btn_pressed) {
                return State{ .menu = .{} };
            }
            return null;
        },
    }
}

fn render(state: *State) void {
    switch (state.*) {
        .menu => |*m| renderMenu(m),
        .playing => |*p| renderPlaying(p),
        .game_over => |*g| renderGameOver(g),
    }
    fun.ssd1306.refresh() catch {};
}

// -------- main ---------------------------------------------------------

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();
    fun.input.initButtonPd1Pullup();

    // ブザー (任意)
    fun.gpio.pin(.D, 4).configure(.output_af_pp_10mhz);
    fun.tone.init(.ch1);

    fun.ssd1306.initI2c() catch unreachable;
    fun.ssd1306.initPanel() catch unreachable;

    var state: State = .{ .menu = .{} };
    var prev_btn = false;

    while (true) {
        const edge = buttonEdge(&prev_btn);
        if (step(&state, edge)) |next| state = next;
        render(&state);
        waitFrame();
    }
}
