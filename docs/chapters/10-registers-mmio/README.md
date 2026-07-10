# Chapter 10: MMIO とレジスタ抽象化

## 学習目標

- MMIO (Memory-Mapped I/O) の概念をおさらいする
- `src/periph/registers.zig` がどう CH32V003 のレジスタ群を **Zig の型** に落とし込んでいるかを読み解く
- `extern struct` / `@ptrFromInt` / `*volatile T` がそれぞれ何のために使われているのかを説明できる
- ベースアドレス + フィールドオフセットの設計が、 なぜ「うっかり間違えにくい」のかを理解する

---

## MMIO のおさらい

ARM Cortex-M、 RISC-V、 SH、 ほとんどの組み込み MCU は周辺機能を **MMIO** で公開している。 「特定の物理番地に対する読み書きが、 そのまま周辺レジスタへの操作になる」 という仕組みだ。

CH32V003 では、 例えば GPIO ポート D の出力レジスタは:

- 番地: `0x4001_1410` ( `GPIOD_BASE (= 0x4001_1400)` + オフセット `0x10` )
- 振る舞い: ここに `u32` を書くと PD0〜PD15 の出力が同時に変わる

これを生で扱うと、こうなる:

```c
*(volatile uint32_t *)0x40011410 = 0x00000001;  // PD0 を H
```

ポインタを `volatile` にしないとコンパイラが最適化で消したり、 読み書き順序を入れ替えたりする。

このアプローチは「番地を間違えない」「フィールド名を間違えない」が **完全に開発者責任** になるので、 規模が増えると間違いを生みやすい。 `src/periph/registers.zig` はこれを Zig の **`extern struct`** で型付けし、 ミスを構造化する。

---

## ベースアドレスの宣言

```zig
pub const FLASH_BASE: usize = 0x08000000;
pub const SRAM_BASE: usize = 0x20000000;
pub const PERIPH_BASE: usize = 0x40000000;
pub const CORE_PERIPH_BASE: usize = 0xE0000000;

pub const APB2PERIPH_BASE: usize = PERIPH_BASE + 0x10000;
pub const APB1PERIPH_BASE: usize = PERIPH_BASE;
pub const AHBPERIPH_BASE: usize = PERIPH_BASE + 0x20000;

pub const GPIOA_BASE: usize = APB2PERIPH_BASE + 0x0800;
pub const GPIOC_BASE: usize = APB2PERIPH_BASE + 0x1000;
pub const GPIOD_BASE: usize = APB2PERIPH_BASE + 0x1400;
pub const I2C1_BASE: usize = APB1PERIPH_BASE + 0x5400;

pub const RCC_BASE: usize = AHBPERIPH_BASE + 0x1000;
pub const FLASH_R_BASE: usize = AHBPERIPH_BASE + 0x2000;

pub const PFIC_BASE: usize = CORE_PERIPH_BASE + 0xE000;
pub const SYSTICK_BASE: usize = CORE_PERIPH_BASE + 0xF000;
```

ここでやっていることは:

1. **メモリ空間全体のセクションベース** (FLASH / SRAM / 周辺 / コア内蔵周辺) を定数化
2. **バスごとのベース** (APB1 / APB2 / AHB) を派生
3. **個別周辺のベース** をさらに派生

CH32V003 のデータシートのメモリマップ表をそのまま Zig の `const` に写したものだ。 `usize` で書いておくことで、 ポインタへの変換が型付きで通る (`@ptrFromInt` の引数として直接使える)。

---

## レジスタブロックを `extern struct` で記述

代表例として RCC (Reset and Clock Control) のレジスタ群。

```zig
pub const RccRegs = extern struct {
    CTLR: u32,
    CFGR0: u32,
    INTR: u32,
    APB2PRSTR: u32,
    APB1PRSTR: u32,
    AHBPCENR: u32,
    APB2PCENR: u32,
    APB1PCENR: u32,
    RESERVED0: u32,
    RSTSCKR: u32,
};
```

ポイント:

- **`extern struct`** は C ABI に準拠したレイアウトを保証する。 Zig の通常 `struct` だとフィールド並び替えが起こる可能性があるが、 `extern struct` ではフィールド順 = メモリ上の順。
- **フィールド順 = データシートのオフセット表の順**。 RCC の場合、 オフセット 0x00, 0x04, 0x08, ... と並ぶレジスタを単に上から書いていけばよい。
- **`RESERVED0: u32`** で予約領域を埋める。 これがあるおかげで、後続フィールドのオフセットがズレない。
- **アライメント** は自然に整う。 `u32` だけで構成しているなら 4 バイト境界に揃う。

---

## I2C のように 16-bit レジスタが並ぶケース

```zig
pub const I2cRegs = extern struct {
    CTLR1: u16,
    RESERVED0: u16,
    CTLR2: u16,
    RESERVED1: u16,
    OADDR1: u16,
    RESERVED2: u16,
    OADDR2: u16,
    RESERVED3: u16,
    DATAR: u16,
    RESERVED4: u16,
    STAR1: u16,
    RESERVED5: u16,
    STAR2: u16,
    RESERVED6: u16,
    CKCFGR: u16,
    RESERVED7: u16,
};
```

CH32V の I2C は **「16-bit レジスタが 4 バイトおきに並ぶ」** という変則レイアウト。 これを忠実に表現するため、 各 `u16` の後ろに `RESERVED?: u16` を入れて 4 バイトに揃えている。 こうすると `i2c1().CTLR2 = ...` のような自然な記述が、 正しい番地への 16-bit 書き込みになる。

---

## ベース番地を `*volatile T` に変換するヘルパ

```zig
pub fn rcc() *volatile RccRegs {
    return @ptrFromInt(RCC_BASE);
}

pub fn gpioA() *volatile GpioRegs {
    return @ptrFromInt(GPIOA_BASE);
}

pub fn i2c1() *volatile I2cRegs {
    return @ptrFromInt(I2C1_BASE);
}

pub fn systick() *volatile SysTickRegs {
    return @ptrFromInt(SYSTICK_BASE);
}
```

- **`@ptrFromInt(addr)`** — 整数を「型付きポインタ」に変換する Zig の組み込み関数。 戻り型が `*volatile RccRegs` なら、 そのアドレスを RCC レジスタブロックへのポインタとみなす。
- **`*volatile T`** — 「`T` への volatile ポインタ」。 経由する読み書きは最適化で消されたり並び替えられたりしない。

呼び出し側はこうなる:

```zig
const rcc = regs.rcc();
rcc.APB2PCENR |= regs.RCC_APB2_GPIOD;
```

これだけで `0x4002_1018 |= 0x00000020` 相当の書き込みが正しく発行される。 番地もシフト幅も書き間違える余地が無い。

---

## ビットマスクは別途定数で

```zig
pub const RCC_APB2_AFIO:  u32 = 0x00000001;
pub const RCC_APB2_GPIOA: u32 = 0x00000004;
pub const RCC_APB2_GPIOC: u32 = 0x00000010;
pub const RCC_APB2_GPIOD: u32 = 0x00000020;
pub const RCC_APB1_I2C1:  u32 = 0x00200000;
```

ビットマスクを **コードシンボルとして名前付け**しておくのが、 数値ベタ書きとの大きな違い。 これがあると `grep` や IDE のジャンプで「このビットを使っている箇所」を一発で見つけられる。 命名規則は「ペリフェラル_バス_機能」とすると、同じ APB2 系のクロックを横断的に見たくなったときに揃って並ぶ。

---

## PFIC の有効化 — 動的にアドレスを作る例

```zig
pub fn pficEnableIrq(irqn: u8) void {
    const reg_index: usize = irqn / 32;
    const bit: u32 = @as(u32, 1) << @as(u5, @intCast(irqn % 32));
    const addr = PFIC_BASE + 0x100 + (reg_index * 4);
    const reg: *volatile u32 = @ptrFromInt(addr);
    reg.* = bit;
}
```

PFIC の IENR (Interrupt Enable Register) は 32 ビット幅 × 複数本という構成で、 IRQ 番号によって書き込むレジスタが変わる。 これを毎回専用の `extern struct` フィールドに割り付けるのは面倒なので、 ここだけは **アドレス計算で動的にポインタを作る**書き方をしている。

`@as(u5, @intCast(irqn % 32))` の `u5` キャストは、 RISC-V の論理シフト命令が「シフト量は下位 5 ビットだけ意味を持つ」 ことを Zig の型システム上で表現するためのもの。 余計な広い型でシフトしようとすると Zig のコンパイラが文句を言うので、 明示的に絞っている。

---

## なぜこの抽象化が「ちょうど良い」のか

他言語 / 他フレームワークでは、 以下のような重い抽象化もよく見る:

- HAL ライブラリ (STM32CubeMX 系) — 各レジスタを構造化したうえで、 さらに `HAL_GPIO_Init(GPIOA, &init_typedef)` のような high-level API を被せる
- Rust の `svd2rust` — SVD XML から自動生成された型安全なレジスタアクセス API

これらは安全性と表現力で勝るが、 学習コストとコードサイズで重くなる。 一方、 本プロジェクトはあくまで「MCU の生のレジスタ表を Zig の `extern struct` に写経した、 ごく薄いレイヤ」に留めている。 これにより:

- データシートと 1:1 で照合できる (調査・デバッグが楽)
- ビット幅・オフセットを把握しているなら、 ほぼ生 C と同じ手触り
- HAL レイヤを上にどう被せるかは別途自由に設計できる (本プロジェクトは `src/hal/*.zig`)

「ちょうど薄く、 ちょうど型安全」という塩梅で、 教育・実験目的のコードベースに向いた抽象度になっている。

---

## まとめ

- ベースアドレス + `extern struct` + `@ptrFromInt` + `*volatile T` の組み合わせで、 MMIO を **データシートとほぼ 1:1 の Zig 型** に落とし込んでいる
- 予約領域は `RESERVED?: u32` のようなフィールドで埋め、 オフセットを保つ
- ビットマスクはシンボル名で定数化することで、 「どこで何のビットを使っているか」が grep 可能になる
- PFIC のように動的なアドレス計算が必要な箇所は、 個別関数で吸収

次章では、 この薄いレジスタ層の上に被せた **HAL (GPIO / SysTick / 入力)** を読んでいき、 アプリ層から見たときの API がどう作られているかを見る。
