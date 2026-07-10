# Chapter 13: 本プロジェクトで使える Zig 言語機能と std

## 学習目標

- 「Zig が書ける」ことと「**この環境で**動く Zig が書ける」ことの差を把握する
- 本プロジェクト (`freestanding` + `link_libc=false` + RV32EC + RAM 2KB) で 安全に使える言語機能 / std の範囲を知る
- 動くがコードサイズ・RAM を急に食う機能 (Debug ビルドの panic、大きい型、format) の特徴を知る
- 「使ったらまずビルドが通らない」「ビルドは通るが実行で破綻する」を見分けられるようになる

---

## 結論を先に

本プロジェクトでファームウェアを書くとき、 ざっくりこういう分類になる:

| 分類 | 代表例 |
|---|---|
| 💚 そのまま使ってよい | 言語の型システム全般、`comptime`、`packed struct`、`extern struct`、`inline for`、`@import("builtin")`、`std.mem` / `std.math` / `std.fmt.bufPrint` / `std.meta` / `std.heap.FixedBufferAllocator` / `std.ArrayList` (allocator 渡し)、 インラインアセンブリ |
| 🟡 慎重に使う | 浮動小数点演算、 64-bit 整数、 `std.AutoHashMap`、 Debug ビルドの panic 経路 |
| 🔴 そもそもビルドが通らない | `std.debug.print` / `std.fs.*` / `std.Thread` / `std.process` / `std.os` 系の OS API、 `std.heap.GeneralPurposeAllocator` (実体は `DebugAllocator` で、freestanding では取れない要素を要求) |
| ⚠️ 通るが事故を起こしやすい | グローバル可変状態の野放しな使用、 「ヒープ」の概念を期待する API、 例外/エラー系で巨大なフォーマッタが走る経路 |

以降、 それぞれを「なぜ」「どこまで」「どう代替」の観点で見ていく。

---

## 大原則: `freestanding` には OS が無い

本プロジェクトのターゲットは:

```
riscv32-unknown-none-eabi (RV32EC, freestanding, eabi, link_libc=false)
```

`freestanding` は「**標準的な OS が無い**」を意味する。これに伴い:

- システムコールが無い → `std.fs` / `std.process` / `std.Thread` / `std.net` は **コンパイル自体が通らない** (`@compileError` で明示的にブロックされる)
- 標準入出力 (`stdout` / `stderr`) が無い → `std.debug.print` も同様にコンパイル不可
- ページアロケータが無い → `std.heap.page_allocator` を要求するアロケータは使えない

これらは「freestanding でも動くように Zig 側が用意してくれている逃げ道」 を意識して回避することになる:

- 「ヒープが要る」 → `FixedBufferAllocator` (任意のバイト配列を裏に持つ)
- 「ログを吐きたい」 → 自前で UART/SWO/SWD-Printf を実装、 または ITM。 本プロジェクトには現状その経路は無い (`fmt.bufPrint` でバッファに書いて自前送信するパターン)
- 「並行処理が欲しい」 → SysTick + 割り込み、 もしくは協調マルチタスクを自前で組む

---

## 言語機能 — そのまま使えるもの

### `comptime` / ジェネリクス

これは本プロジェクトの骨子で多用されている。 例:

```zig
// build.zig 内で「known examples」 を inline for で走査
inline for (examples) |example| {
    if (std.mem.eql(u8, name, example.name)) return example;
}

// ベクタテーブルは comptime に組み上がって ELF に焼き込まれる
fn makeVectorTable() [39]?*const anyopaque {
    var table = [_]?*const anyopaque{null} ** 39;
    table[2] = &_default_irq_entry;
    // ...
    return table;
}
pub export const vector_table linksection(".vector_table") = makeVectorTable();
```

`comptime` で式が解決できる限り、**ランタイムコストはゼロ**。 MCU 向けにこれほど嬉しい言語機能はない。

### `packed struct(u8)` と `extern struct`

MMIO レイアウトの記述に欠かせない。 本プロジェクトでは `extern struct` をフィールド並びの保証として、 一部のフラグ表現には `packed struct(uN)` を使える。

```zig
const Flags = packed struct(u8) {
    a: bool,
    b: bool,
    rest: u6,
};

const raw: u8 = @bitCast(Flags{ .a = true, .b = true, .rest = 0 });
```

- `extern struct` — フィールド順 = メモリ順、 自然アライン。 C 互換。
- `packed struct(uN)` — ビット幅を明示し、ビットフィールドのように扱える。 `@bitCast` で生のスカラに戻せる。

### `optional` / `error union` / `tagged union`

普通に使える。 ただし「`!T` のエラーを `format` 越しに文字列化する」と、 内部的に複雑なフォーマッタが引きずられる可能性があるので注意 (後述)。

```zig
const T = union(enum) { a: u8, b: u16 };
const t: T = .{ .b = 100 };
switch (t) {
    .a => |v| ...,
    .b => |v| ...,
}
```

### インラインアセンブリ

`asm volatile (...)` が使え、 CSR 操作 / 割り込み制御 / 起動コードに必須。 第 5・6 章で詳説した通り。

### `@import("builtin")` で得られる情報

```zig
const builtin = @import("builtin");

if (builtin.os.tag == .freestanding) {
    // ターゲット依存の分岐
}
if (builtin.mode == .Debug) {
    // Debug ビルド時だけのコード
}
const endian = builtin.cpu.arch.endian();
```

`builtin` 経由でターゲット情報を取り、 `comptime` 分岐すれば、 ビルド時にコード分岐が解決されてランタイムコストがかからない。

### `@intCast` / `@truncate` / `@bitCast` / `@as`

整数の幅・型の変換が明示的に書ける。 0.16 では「黙って広がる/縮む」キャストは原則禁止になっており、 思った通りの命令が出る確認になる。

```zig
const a: u16 = 0x1234;
const lo: u8 = @truncate(a);          // 下位 8-bit
const sg: i16 = @intCast(@as(i32, -3)); // 範囲チェック付き
const flags: u8 = @bitCast(my_packed_struct);
```

---

## 言語機能 — 注意して使うもの

### 浮動小数点

CH32V003 には FPU が無い。 `f32` / `f64` の計算は、 Zig が **`compiler_rt` のソフトウェア浮動小数点ルーチン** を呼ぶコードに展開する (第 3 章で触れた `bundle_compiler_rt`)。

- **ビルドは通る** — `compiler_rt` が同梱されているため
- **動くは動く** — ただし 1 演算で数百クロック消費するレベル
- **コードサイズが目に見えて増える** — 浮動小数点を 1 か所でも使うと、 `__addsf3` / `__mulsf3` / `__divsf3` などが ELF に乗ってくる

組み込み的には「**整数演算と固定小数点で済むなら、 そのほうがずっと幸せ**」。 SSD1306 の円描画もブレゼンハム整数で書いてある (第 12 章) のはこの方針。

### 64-bit 整数 (`u64` / `i64`)

CH32V003 は 32-bit コア。 64-bit 演算は **二命令以上 + キャリーチェイン** として展開される。 さらに乗除算は `compiler_rt` の `__muldi3` などを使う。

- **ビルドは通る**
- **動く**
- **1 操作あたりのコストは 32-bit の 2〜10 倍**

時刻 (`u64` で tick) のように 32-bit が直近で溢れる用途では正当。 単に「広い方が安心」で 64-bit を選ぶのは、 このターゲットでは贅沢に分類される。

### `std.AutoHashMap` / `std.ArrayList`

- ビルドは通り、 freestanding でも動く (アロケータを引数で受け取るため)
- だが **ハッシュ機構やリサイズが意外と重い**。 2KB の RAM では 数十エントリで枯れる
- 「組み込み向けの薄い HAL」 を作る本プロジェクトの趣旨では、 出番はかなり限定的

### Debug ビルドと panic

Zig は Debug ビルドで:

- 整数オーバーフロー、 配列境界、 タグ不整合などをランタイムで検査
- 失敗すると panic ハンドラを呼ぶ
- 標準の panic ハンドラは「**ファイル名・行番号・スタックトレースを整形してプリント**」しようとする

freestanding ターゲットでも、 「panic 時のフォーマッタとスタックトレース展開コード」 は ELF に乗ってきてしまい、 **数百 KB 〜 MB 単位で `.text` が膨らむ** ことがある。

検証用の最小コードで実測すると:

| 構成 | ELF サイズ (概算) |
|---|---|
| `-O ReleaseSmall` + 自前 panic ハンドラ | 1〜2 KB |
| `-O Debug` + デフォルト panic | **〜2 MB** ELF (=リンク後の `.text` が無視できないサイズに膨らむ) |

本プロジェクトでも、 デフォルト最適化は `ReleaseSmall` にしてある (build.zig の `optimize` のデフォルト)。 Debug でビルドするときは:

- **必ず自前の panic ハンドラ** を root モジュールに置く
  ```zig
  pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
      // LED 点滅 + wfi など、 最低限の合図だけにする
      while (true) {}
  }
  ```
- それでも Debug ビルドの方が大きいので、 16K FLASH に収まらないことがある

「ReleaseSmall でビルド、 デバッグは観測 LED と SWD でやる」 が現実的な落とし所。

---

## 言語機能 — 使えないもの

### `std.debug.print` 系

```zig
std.debug.print("hi\n", .{});
// → error: struct 'posix.system__struct_837' has no member named 'getrandom'
// → コンパイルが通らない
```

`debug.print` は内部で stderr に書き込むため、 freestanding では参照先で `@compileError` が立つ。 ログを取りたければ:

- `std.fmt.bufPrint(&buf, "x={d}", .{x})` でバッファに整形
- そのバイト列を UART / SWO などで自前送信

の 2 段にする。 本プロジェクトには UART HAL は同梱されていないので、 必要なら自分で追加する立場になる。

### `std.fs` / `std.process` / `std.os` 系

```zig
std.fs.cwd().openFile(...)
// → error: root source file struct 'fs' has no member named 'cwd'
```

freestanding ターゲットでは `std.fs.cwd` 自体が存在しない。 「ファイル」「プロセス」「環境変数」 という概念がそもそも無いのだから、 これは正しい挙動。

### `std.Thread`

```zig
_ = std.Thread.spawn(.{}, worker, .{}) catch unreachable;
// → @compileError("Unsupported operating system freestanding");
```

明示的に `@compileError` で止められる。 「並行処理が欲しいなら、 割り込み or 自前のタスクスケジューラを書け」 という設計判断。

### `std.heap.GeneralPurposeAllocator` / `DebugAllocator`

`GeneralPurposeAllocator` は 0.16 で `DebugAllocator` に改名されているが、 いずれにせよ ホスト環境のページアロケータや OS の確保 API を要求するため、 freestanding では使えない。 代替は `FixedBufferAllocator`。

```zig
var pool_bytes: [256]u8 = undefined;

pub fn main() void {
    var fba = std.heap.FixedBufferAllocator.init(&pool_bytes);
    const a = fba.allocator();
    // a を ArrayList / AutoHashMap に渡せる
}
```

「ヒープ」 を `[N]u8` の固定配列に閉じ込めるイメージ。 RAM の使用上限が静的に見える、 ある意味 MCU フレンドリな方法。

### `std.log`

`std.log` は内部で `std.debug.print` 系に依存しているため、 設定しないと freestanding で死ぬ。 どうしても使いたければ `pub const std_options = std.Options{ .logFn = myLog };` で自前の `logFn` を差し込み、 その中で `bufPrint` + 自前送信に流す形になる。 ただし本プロジェクトには現状その配線は無い。

---

## std で使える「組み込み向きの便利な部品」

freestanding でも問題なく動き、 役立つもの一覧:

| 機能 | 用途 |
|---|---|
| `std.mem.eql` / `indexOf` / `sliceTo` / `copyForwards` | バイト/スライス操作 |
| `std.mem.byteSwap` / `nativeToLittle` / `nativeToBig` | エンディアン変換 (通信プロトコル) |
| `std.math.maxInt` / `minInt` / `clamp` / `mod` / `divCeil` | 安全な整数演算 |
| `std.fmt.bufPrint` / `bufPrintZ` | 文字列整形 (UART ログ作る時) |
| `std.fmt.parseInt` / `parseFloat` | 受信した ASCII を数値に |
| `std.meta.fields(T)` / `tagName` / `stringToEnum` | enum / struct の reflection |
| `std.hash.Crc32` / `Adler32` / `XxHash32` | CRC・チェックサム |
| `std.crypto.hash` のいくつか | ハッシュ。 ただし重い |
| `std.heap.FixedBufferAllocator` | スタティック配列を裏に持つアロケータ |
| `std.ArrayList(T)` / `BoundedArray(T, N)` | 可変長配列 / 上限固定可変長配列 |
| `std.io.fixedBufferStream` | バイト列を Writer/Reader に変換 |

「Reader/Writer + bufPrint + Crc32」 の組合せだけで、 シリアルプロトコルの実装はかなり書ける。

---

## 設計判断: いつ std を使い、 いつ自前で書くか

このリポジトリのスタンスは、 「**ハードに触る部分は自前 / アルゴリズム的な部分は std**」。 例えば:

- レジスタアクセス、 割り込みハンドラ、 起動 → 自前 (`src/runtime`, `src/periph`, `src/hal`)
- バイト列のスライス操作、 整数の最大/最小、 ビット演算ヘルパ → std を使ってよい

本プロジェクトのソースは現状 `std` を一切 import していない (HAL の規模が小さいので、 std を引かなくても困らないため)。 ただし 「std 禁止」 ではない。 アプリ側で `std.fmt.bufPrint` を使った UART ロガーを書くなどは正当な選択肢。

---

## チートシート

「迷ったらこれを見る」 用の一覧:

```text
✅ Always OK
   - 言語機能全般 (comptime, generics, packed/extern struct, asm, optional, error union)
   - @import("builtin")
   - std.mem.* (eql, indexOf, sliceTo, copy, swap)
   - std.math.* (整数系)
   - std.fmt.bufPrint / bufPrintZ
   - std.meta.* (fields, tagName, stringToEnum)
   - std.hash.* / std.crypto.hash 系の整数ハッシュ
   - std.heap.FixedBufferAllocator
   - std.ArrayList(T) / BoundedArray(T, N) (allocator は FBA を渡す)
   - std.io.fixedBufferStream

⚠ Use carefully
   - f32/f64 演算 (soft-float, サイズと速度に影響)
   - u64/i64 演算 (32-bit 2 命令展開 + libcall)
   - std.AutoHashMap (RAM 不足になりやすい)
   - std.fmt.allocPrint (要 allocator、フォーマッタ重め)
   - Debug ビルドの panic 経路 (.text が大幅に膨らむ)

❌ Won't compile / Don't use
   - std.debug.print / std.log (内部で OS 依存)
   - std.fs.* / std.process.* / std.os.* / std.posix.*
   - std.Thread (@compileError "freestanding")
   - std.heap.GeneralPurposeAllocator / DebugAllocator
   - std.heap.page_allocator
   - std.net.* / std.http.*
```

---

## まとめ

- `freestanding` + `link_libc=false` + RV32EC + RAM 2KB の制約上、 「**Zig 言語そのものはほぼフル機能、 std はホスト/OS に依存しない部分だけ**」 という線引きになる
- 言語機能 (`comptime` / `packed struct` / 任意ビット幅整数 / インラインアセンブリ) は組み込みに非常に強く、 これを積極的に使うのが本プロジェクトのスタイル
- `std.mem` / `std.math` / `std.fmt.bufPrint` / `std.meta` / `std.heap.FixedBufferAllocator` / `std.ArrayList` あたりは「**OS が無くても動く部品**」として安心して使える
- `std.debug.print` / `std.fs` / `std.Thread` / `GeneralPurposeAllocator` などは **コンパイル時点で弾かれる**。 これは仕様であって不具合ではない
- 浮動小数点と 64-bit は「ビルドは通るが MCU には重い」 という典型例。 必要性を見極めて使う
- Debug ビルドは panic 関連で `.text` が大きく膨らむ。 デフォルトの `ReleaseSmall` で書き、 デバッグは LED と SWD で観測するのが現実的

これで、 本プロジェクト上で **「これを書いたら通る/通らない/動くが太る」** が見通せる状態になる。 各章で見てきた MCU 寄りの薄い HAL と、 ここで挙げた「freestanding で使える Zig の道具立て」を組み合わせれば、 CH32V003 上で達成できる事の幅はずっと広がる。
