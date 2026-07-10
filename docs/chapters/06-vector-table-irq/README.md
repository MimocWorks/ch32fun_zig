# Chapter 06: ベクタテーブルと割り込みエントリ

## 学習目標

- CH32V003 (QingKe) のベクタテーブル構造を把握する
- `makeVectorTable()` が `comptime` 配列で組まれている理由を理解する
- `_systick_irq_entry` の汎用レジスタ退避がなぜあれだけ並んでいるのかを読み解ける
- ベクタ番号 12 が SysTick、 14 がソフトウェアといった「PFIC 側の番号付け」を知る

---

## ベクタテーブルとは

CPU から見ると、 割り込み / 例外が起きると **`mtvec` の指すテーブルからハンドラのアドレスを引き、 PC を飛ばす** ことになる。 「テーブル」の中身は普通、 1 エントリ = 1 ワード (32-bit) の関数ポインタ列だ。

CH32V003 (QingKe RV32EC) では PFIC (Programmable Fast Interrupt Controller) が割り込みを管理する。 ベクタ番号は以下のように決まっている。

| 番号 | 意味 |
|---|---|
| 0 | (リセットエントリ。実質ここに `_start` が来るよう vector_table[0] を仕込む) |
| 2 | NMI |
| 3 | Hard Fault / Exception |
| 12 | SysTick |
| 14 | Software (PendSV 相当) |
| 16〜 | 周辺割り込み (各 IRQ 番号) |

本プロジェクトでは、 38 までを並べた長さ 39 の関数ポインタ配列を作っている。

---

## `makeVectorTable()` — `comptime` でテーブルを組む

```zig
fn makeVectorTable() [39]?*const anyopaque {
    var table = [_]?*const anyopaque{null} ** 39;
    table[2] = &_default_irq_entry;   // NMI
    table[3] = &_default_irq_entry;   // Exception
    table[12] = &_systick_irq_entry;  // SysTick
    table[14] = &_default_irq_entry;  // Software

    var i: usize = 16;
    while (i < table.len) : (i += 1) {
        table[i] = &_default_irq_entry;
    }

    return table;
}

pub export const vector_table linksection(".vector_table") = makeVectorTable();
```

### ポイント

- **`?*const anyopaque`** — 「不透明な関数ポインタ、または null」。 ベクタは関数ポインタとしてだけ意味があるので、 型は緩めにして良い。
- **`comptime` 配列構築** — Zig 0.16 では、 グローバル `const` の初期化式は `comptime` で評価される。 つまり `makeVectorTable()` の呼び出しはランタイムには走らず、 **コンパイル時にテーブルが組み上がる**。 結果として ELF に静的データとして焼き込まれる。
- **`linksection(".vector_table")`** — リンカスクリプトの `.vector_table` セクションに置く指示。 第 4 章で `KEEP(*(.vector_table))` していたのと対応する。
- **長さ 39** — 「16 (システム例外) + 23 (CH32V003 が使う最大の周辺 IRQ 番号 + α)」というつもりの数。 余分なエントリも `&_default_irq_entry` で埋めて、 万一不意の割り込みが来てもベクタアドレスとして null を踏まないようにしている。

### `_default_irq_entry`

```zig
pub export fn _default_irq_entry() callconv(.naked) void {
    asm volatile (
        \\j _default_irq_body
    );
}

export fn _default_irq_body() callconv(.c) noreturn {
    defaultInterruptBody();
    unreachable;
}

fn defaultInterruptBody() callconv(.c) void {
    while (true) {
        asm volatile ("wfi");
    }
}
```

「予期しない割り込みが来た時のフォールバック」。 単に `wfi` (Wait For Interrupt) を回し続けて寝る。 デバッグ時にはここに来ていることがブレークで分かるので、 「何かよくわからん割り込みで死んでいる」状態の検知ポイントになる。

---

## SysTick 割り込みの作法

```zig
pub export fn _systick_irq_entry() callconv(.naked) void {
    asm volatile (
        \\addi sp, sp, -128
        \\sw ra, 124(sp)
        \\sw gp, 120(sp)
        \\sw tp, 116(sp)
        \\sw t0, 112(sp)
        ... (caller-saved + callee-saved 全保存)
        \\call _systick_irq_body
        ... (全部 lw で復元)
        \\addi sp, sp, 128
        \\mret
    );
}

export fn _systick_irq_body() callconv(.c) void {
    time.systickInterruptBody();
}
```

### なぜ全レジスタを退避するのか

第 5 章で `mtvec` に `0x3` (= ベクタード + ハードウェアスタッキング) モードを設定したものの、 ハードがスタッキングしてくれる対象は限られている。 加えて Zig 側で呼ばれる `_systick_irq_body` は普通の `callconv(.c)` 関数で、 内部で任意のレジスタを破壊する可能性がある。

そのため、 ハンドラの先頭で **t0〜t6 / a0〜a7 / s0〜s11 / ra / gp / tp** を全て退避し、 末尾でまとめて復元する形にしている。

| 種別 | レジスタ |
|---|---|
| 呼び出し規約上 caller-saved (壊しても良いが今は退避が要る) | `t0`〜`t6`, `a0`〜`a7`, `ra` |
| callee-saved (Zig の通常関数が壊さない) | `s0`〜`s11`, `gp`, `tp` |

callee-saved 側は、 厳密には `_systick_irq_body` 側で必要な分だけ保存される。 だが「割り込みハンドラからの戻りで `mret` するだけ」なら、 ハンドラ内で **全部を退避する方が安全** で、 ステートマシン的に分かりやすい。

### `mret`

`ret` ではなく `mret` で戻るのが割り込みハンドラの作法。 `mret` は:

- `mstatus.MIE` を `mstatus.MPIE` の値で復元
- 特権レベルを `mstatus.MPP` で復元
- PC を `mepc` の値に戻す

を一気に行う命令で、 まさに「割り込みから戻る」ことの本体になる。

---

## SysTick ボディの実装

```zig
export fn _systick_irq_body() callconv(.c) void {
    time.systickInterruptBody();
}
```

```zig
// src/hal/time.zig
pub fn systickInterruptBody() callconv(.c) void {
    const st = regs.systick();

    st.CMP +%= systick_ticks_per_irq;
    st.SR = 0;
    systick_ticks +%= 1;

    if (tick_handler) |handler| {
        handler();
    }
}
```

- `CMP` を次の発火地点に進める
- `SR` を 0 にしてラッチをクリア
- ティックカウンタをインクリメント
- 登録されたユーザコールバックがあれば呼ぶ

「割り込みハンドラの中で重い処理をしない」のが定石どおりで、 実体は HAL に閉じ込めている。

---

## ベクタ番号と `pficEnableIrq`

ベクタ番号に対応する IRQ ラインを **PFIC 側で個別に有効化**しない限り、 当該割り込みは入ってこない。 その仕事をしているのが:

```zig
// src/periph/registers.zig
pub fn pficEnableIrq(irqn: u8) void {
    const reg_index: usize = irqn / 32;
    const bit: u32 = @as(u32, 1) << @as(u5, @intCast(irqn % 32));
    const addr = PFIC_BASE + 0x100 + (reg_index * 4);
    const reg: *volatile u32 = @ptrFromInt(addr);
    reg.* = bit;
}
```

- IRQ 番号を 32 で割って、 PFIC の有効化レジスタ群 (`IENR0`, `IENR1`, ...) のインデックスを得る
- 32 で割った余りでビット位置を計算
- そのビットだけ立てる (PFIC の有効化レジスタは「1 を書くと立つ」セットレジスタなので、 RMW しなくて良い)

`SysTick` だけは少し特殊で、 vector_table から直接ハンドラに飛ぶようになっているので、 通常用途では明示的に `pficEnableIrq(12)` を呼ぶ必要が無く、 `mstatus.MIE` と SysTick の `STIE` を立てれば走り始める。

---

## まとめ

- ベクタテーブルは長さ 39 の関数ポインタ配列で、 `comptime` に組まれて `.vector_table` セクションに焼かれる
- 不要なエントリ含め全部 `_default_irq_entry` で埋めることで、 予期しない割り込みでも `wfi` ループに入って暴走しないようにしている
- SysTick ハンドラはレジスタ全退避 + `mret` で、 通常 Zig 関数からの呼び出しが安全になるよう作られている
- 周辺 IRQ を有効化する際には `pficEnableIrq(n)` で個別ビットを立てる

ここまでで「リセットからユーザコードまで走る経路」「割り込みが正しく入る経路」が揃ったので、 次章からは **ビルド側のパイプライン** に視点を移し、 `build.zig` がこれらを ELF にまとめ上げる手順を見ていく。
