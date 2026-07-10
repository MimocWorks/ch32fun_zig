//! 圧電ブザーで簡単なメロディを鳴らす。
//! 配線: ブザー → PD4 (TIM2_CH1) と GND の間。

const fun = @import("ch32fun");

const Note = struct { freq: u32, ms: u32 };

const C4 = 262;
const D4 = 294;
const E4 = 330;
const F4 = 349;
const G4 = 392;
const A4 = 440;
const B4 = 494;
const C5 = 523;

const song = [_]Note{
    .{ .freq = C4, .ms = 200 },
    .{ .freq = D4, .ms = 200 },
    .{ .freq = E4, .ms = 200 },
    .{ .freq = F4, .ms = 200 },
    .{ .freq = G4, .ms = 200 },
    .{ .freq = A4, .ms = 200 },
    .{ .freq = B4, .ms = 200 },
    .{ .freq = C5, .ms = 400 },
    .{ .freq = 0, .ms = 600 }, // silence
};

pub export fn _start() noreturn {
    main();
}

pub fn main() noreturn {
    fun.system.init(.{});
    fun.gpio.enableAllClocks();

    // TIM2_CH1 = PD4
    fun.gpio.pin(.D, 4).configure(.output_af_pp_10mhz);
    fun.tone.init(.ch1);

    while (true) {
        for (song) |note| {
            fun.tone.play(note.freq, note.ms);
        }
    }
}
