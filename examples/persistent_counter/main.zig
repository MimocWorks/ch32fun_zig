//! persistent_counter
//!
//! 起動回数を FLASH 末尾の 1 ページ (64B) に書き込み、
//! その値ぶんだけ LED (PD0) を点滅させる。 リセットや電源 OFF を挟んでも
//! 値はリセットされない。
//!
//! 永続化のサイクル:
//!   1) Slot(Counter).load() で前回値を読む。 無ければ 0 で初期化
//!   2) +1 して save
//!   3) LED を value 回点滅
//!   4) しばらく待つループに入る (フラッシュ寿命を保護するため、
//!      電源を入れっぱなしの間は再保存しない)
//!
//! ⚠ フラッシュは 10,000 回程度しか書き換えに耐えない。
//!    実用では「終了時に 1 回だけ保存」「数 10 分に 1 回保存」など、
//!    必ず書き込み頻度を絞ること。

const fun = @import("ch32fun");

const Counter = extern struct {
    boots: u32,
    last_score: u32,
};

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    const led = fun.gpio.pin(.D, 0);
    led.configure(.output_pp_10mhz);

    // 起動回数を読み出して +1 して保存
    const slot = fun.flash.Slot(Counter).default(1);
    var c = slot.loadOrInit(.{ .boots = 0, .last_score = 0 }) catch Counter{
        .boots = 0,
        .last_score = 0,
    };
    c.boots +%= 1;
    slot.save(c) catch {
        // 書き込みに失敗しても先に進める。 LED 高速点滅でエラーを通知
        var i: u8 = 0;
        while (i < 20) : (i += 1) {
            led.toggle();
            fun.time.delayMs(50);
        }
    };

    // 起動回数ぶん LED を「短点滅」 (1 周期 = 200ms ON + 200ms OFF)
    var n: u32 = 0;
    while (n < c.boots) : (n += 1) {
        led.write(true);
        fun.time.delayMs(200);
        led.write(false);
        fun.time.delayMs(200);
    }

    // 区切りの長休止 → 以降は緩やかに点滅して「電源は入っている」サインを出す
    fun.time.delayMs(1500);
    while (true) {
        led.toggle();
        fun.time.delayMs(1000);
    }
}
