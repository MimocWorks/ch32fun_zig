//! compile_time_morse
//!
//! 「文字列をモールス符号で送信する」 という処理を、 ランタイム解析無しで
//! 完全に **comptime 展開** するデモ。
//!
//!   const pattern = comptime morseEncode("HELLO ");
//!
//! によって `pattern` は ROM 上の `[N]Element` リテラル列になり、 実機で
//! 走るループは「事前に並んだ配列を順に LED に出すだけ」 になる。
//! つまり「文字 → モールス変換」 のコストは **0 命令 / 0 バイトの RAM**。
//!
//! 配線: LED アノード → 抵抗 → PD0、 カソード → GND。
//!       ボタンは無し。

const std = @import("std");
const fun = @import("ch32fun");

// 1 単位の長さ (= "dit" の長さ、 ms)
const unit_ms: u32 = 120;

// モールスの 1 要素を tagged union で表現する。 各要素は ON 時間と
// OFF 時間 (= 次までの間隔) を持つ。
const Element = union(enum) {
    dit, // 1u ON, 1u OFF
    dah, // 3u ON, 1u OFF
    letter_gap, // 0u ON, 2u OFF (直前の elem 後の 1u と合わせて 3u)
    word_gap, //   0u ON, 4u OFF (合計で 7u)
};

/// 1 文字 → モールス文字列 ("." と "-" の連なり) のテーブル。
/// comptime にしか使われない値なので、 RAM には乗らない。
fn morseFor(ch: u8) ?[]const u8 {
    return switch (std.ascii.toUpper(ch)) {
        'A' => ".-",
        'B' => "-...",
        'C' => "-.-.",
        'D' => "-..",
        'E' => ".",
        'F' => "..-.",
        'G' => "--.",
        'H' => "....",
        'I' => "..",
        'J' => ".---",
        'K' => "-.-",
        'L' => ".-..",
        'M' => "--",
        'N' => "-.",
        'O' => "---",
        'P' => ".--.",
        'Q' => "--.-",
        'R' => ".-.",
        'S' => "...",
        'T' => "-",
        'U' => "..-",
        'V' => "...-",
        'W' => ".--",
        'X' => "-..-",
        'Y' => "-.--",
        'Z' => "--..",
        '0' => "-----",
        '1' => ".----",
        '2' => "..---",
        '3' => "...--",
        '4' => "....-",
        '5' => ".....",
        '6' => "-....",
        '7' => "--...",
        '8' => "---..",
        '9' => "----.",
        ' ' => "",
        else => null,
    };
}

/// comptime で文字列を Element 列に展開する。
/// 戻り値は `*const [N]Element` で、 ROM に乗る。
fn morseEncode(comptime text: []const u8) []const Element {
    comptime {
        var elems: []const Element = &.{};
        for (text, 0..) |ch, idx| {
            if (ch == ' ') {
                elems = elems ++ &[_]Element{.word_gap};
                continue;
            }
            const code = morseFor(ch) orelse continue;
            for (code) |c| {
                elems = elems ++ &[_]Element{switch (c) {
                    '.' => .dit,
                    '-' => .dah,
                    else => unreachable,
                }};
            }
            // 次の文字との区切り (最後の文字を除く)
            if (idx + 1 < text.len and text[idx + 1] != ' ') {
                elems = elems ++ &[_]Element{.letter_gap};
            }
        }
        return elems;
    }
}

const Pin = @TypeOf(fun.gpio.pin(.D, 0));

fn emit(led: Pin, e: Element) void {
    switch (e) {
        .dit => {
            led.write(true);
            fun.time.delayMs(unit_ms);
            led.write(false);
            fun.time.delayMs(unit_ms);
        },
        .dah => {
            led.write(true);
            fun.time.delayMs(unit_ms * 3);
            led.write(false);
            fun.time.delayMs(unit_ms);
        },
        .letter_gap => {
            // 直前の 1u と合わせて 3u に
            fun.time.delayMs(unit_ms * 2);
        },
        .word_gap => {
            fun.time.delayMs(unit_ms * 4);
        },
    }
}

const message = morseEncode("HELLO ZIG ");

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    const led = fun.gpio.pin(.D, 0);
    led.configure(.output_pp_10mhz);

    while (true) {
        for (message) |e| emit(led, e);
        // メッセージ全体の終わりにさらに長く休む
        fun.time.delayMs(unit_ms * 14);
    }
}
