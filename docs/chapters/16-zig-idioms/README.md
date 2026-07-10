# Chapter 16: Zig 言語機能を活かしたファームウェアパターン

## 学習目標

- `comptime` がコードサイズ・RAM 使用量にどう効くかを 4 つのサンプルで実感する
- `tagged union` + 網羅 `switch` でステートマシンを書くと、 何が嬉しいのか分かる
- `packed struct(uN)` + `@bitCast` で「ビット幅を意識した型」 を実用化する
- 13 章のチェックリスト的な解説を、 動くコードで補強する

---

## 4 つのサンプル

| # | サンプル | 主な Zig 機能 | bin サイズ |
|---|---|---|---:|
| A | `compile_time_morse` | `comptime` 文字列展開、 tagged union | 0.5 KB |
| B | `state_machine_game` | tagged union + 網羅 switch、 飽和加算 `+\|=` | 6.0 KB (OLED 込み) |
| C | `packed_settings` | `packed struct(u32)`、 `@bitCast`、 Flash Slot | 1.7 KB |
| D | `comptime_lookup` | `comptime` で sin テーブル生成、 `.rodata` 配置 | 0.8 KB |

それぞれは独立して動く小品。 「Zig だから書けた」 部分を意識して読むと教材価値が高い。

---

## A: `compile_time_morse` — 文字列 → モールス符号を *コンパイル時* に展開

### 何が嬉しいか

- 「文字 → モールス変換ロジック」 は **コンパイル時に消える**
- 実機で走るのは 「事前に並んだ `Element` 配列を順に出すループ」 だけ
- 変換コストは 0 命令 / 0 バイトの RAM。 一方、 普通の C で書こうとすると、 ランタイムの `switch` か LUT 引きが残ってしまう

### キーになる部分

```zig
const Element = union(enum) { dit, dah, letter_gap, word_gap };

fn morseEncode(comptime text: []const u8) []const Element {
    comptime {
        var elems: []const Element = &.{};
        for (text, 0..) |ch, idx| {
            const code = morseFor(ch) orelse continue;
            for (code) |c| {
                elems = elems ++ &[_]Element{switch (c) {
                    '.' => .dit,
                    '-' => .dah,
                    else => unreachable,
                }};
            }
            if (idx + 1 < text.len and text[idx + 1] != ' ') {
                elems = elems ++ &[_]Element{.letter_gap};
            }
        }
        return elems;
    }
}

const message = morseEncode("HELLO ZIG ");  // ← ROM に焼かれる配列
```

- `morseEncode` は **`comptime` ブロックで全部評価される**。 `text` は `comptime []const u8` (= 文字列リテラル) として渡ってくる。
- 配列の連結 `++` は comptime に許される操作。 結果は固定長の `[]const Element` リテラルとして `message` に紐付く。
- 実機上の `for (message) |e| emit(led, e);` は、 ROM 上の配列要素を `switch` で分岐するだけの単純なループに翻訳される。

### 改変アイデア

- `Element` に「周波数」 を持たせて、 LED ではなくブザーで送信する版に
- `text` を別のメッセージに差し替えて、 自分の名前を SOS 風に送る

---

## B: `state_machine_game` — tagged union でステートを表現

### 何が嬉しいか

C で書くと「`int state;` + `enum { MENU, PLAYING, GAME_OVER }`」 + 「ステートごとに別の構造体」 を別々のグローバルとして並べることになりがち。 Zig の **`union(enum)`** はそれらを 1 つの「ステート」型として束ね、

```zig
const State = union(enum) {
    menu: Menu,
    playing: Playing,
    game_over: GameOver,
};
```

と書ける。 そして `switch (state.*)` を書くと、 **すべてのバリアントを処理しないとコンパイルエラー** になる。 新しいステート (`paused` など) を追加した瞬間、 「`render` / `step` の両方を直してくれ」 と Zig が怒ってくれる。 これは大規模化したファームのバグ予防に効く。

### キーになる部分

```zig
fn step(state: *State, btn_pressed: bool) ?State {
    switch (state.*) {
        .menu => |*m| { /* ... */ },
        .playing => |*p| {
            if (btn_pressed) {
                if (in_sweet) {
                    p.score +|= 1;  // 飽和加算: u16 オーバーフローでパニックしない
                    // ...
                }
            }
            return null;
        },
        .game_over => |*g| { /* ... */ },
    }
}
```

- `.playing => |*p|` で **そのバリアントの中身へのポインタ** が取れる。 これでスコアやミス数をその場で書き換えられる
- `+|=` (飽和加算) は Zig の組み込み演算子。 `u16` の上限 65535 を超えても勝手にラップ/パニックしない。 ゲームスコアのような「定義域を絶対超えてほしくない」 値に向く
- ステート遷移は `return State{ .game_over = .{ ... } };` の形で **値を返す** スタイル。 グローバルを書き換えずに済むので、 振る舞いを読みやすい

### サイズ

OLED ドライバ込みで 6KB。 これは `oled` サンプルとほぼ同じで、 ステートマシン部分そのものの追加コストはごくわずか。

### 改変アイデア

- `Paused` ステートを追加してみる → コンパイラに何箇所怒られるかを観察するとよい教材
- スイートスポットの幅を `Playing` の中に持たせ、 段階的に難しくする

---

## C: `packed_settings` — `packed struct(u32)` を Flash に保存

### 何が嬉しいか

設定一式 (動作モード / 明るさ / ブザーオン・オフ / ボリューム / 保存回数 / レビジョン) を **u32 1 ワード** にビット幅指定で詰める:

```zig
const Settings = packed struct(u32) {
    mode: LedMode,    // 3 bit
    brightness: u4,   // 4 bit
    buzzer: bool,     // 1 bit
    volume: u4,       // 4 bit
    save_count: u12,  // 12 bit
    revision: u8,     // 8 bit
};

comptime {
    if (@sizeOf(Settings) != 4) @compileError("Settings must fit in u32");
}
```

- `packed struct(u32)` の **`(u32)` は「全フィールド合計でちょうど 32-bit になることをコンパイラに検証させる」**。 ビット幅の積み上げを 1 ビットでも間違えるとコンパイルエラー
- `comptime { ... @compileError }` で 「サイズ ≠ 4 ならビルド失敗」 とダメ押しの保険
- `@bitCast(u32, settings)` でスカラに、 逆方向もキャスト 1 回 ↔ struct

Flash 永続化との相性が良く、 第14章の `Slot(T)` に `T = Settings` を渡すだけで設定保存が完成する。

### キーになる部分

```zig
const initial: Settings = .{
    .mode = .slow_blink,
    .brightness = 8,
    .buzzer = true,
    .volume = 4,
    .save_count = 0,
    .revision = 1,
};

fn loadSettings() Settings {
    return settingsSlot().load() orelse initial;
}

// ボタン押下が落ち着いたタイミングだけ Flash に書く (寿命対策)
if (dirty and debounce == 0) {
    saveSettings(s);
    dirty = false;
}
```

`packed struct` で必要なビット幅だけを宣言しているので、 構造的に不正な値 (`mode = 99` のような) が **入りようがない**。 これは C のビットフィールドにありがちな「コンパイラ依存のレイアウト」 を排除した、 Zig の良いところ。

### 改変アイデア

- フィールドを増やしてもサイズが 32-bit に収まり続けるか、 `@compileError` で検査
- 8-bit MCU 向けに `packed struct(u16)` 版にして比較してみる

---

## D: `comptime_lookup` — `sin` テーブルをコンパイル時に作る

### 何が嬉しいか

LED の呼吸 (フェード) には sin 関数が向いているが、 CH32V003 には FPU が無く、 sin 計算はソフトウェア float で重い。 Zig の `comptime` なら、 **テーブルそのものをビルド時に生成** して `.rodata` に焼ける。

```zig
fn buildBreathTable() [table_len]u16 {
    @setEvalBranchQuota(200_000);
    var out: [table_len]u16 = undefined;
    var i: usize = 0;
    while (i < table_len) : (i += 1) {
        const phase: f32 = @as(f32, @floatFromInt(i)) / @as(f32, table_len);
        const s = @sin(phase * std.math.pi);
        const lin = s * s;
        const corrected = std.math.pow(f32, lin, gamma);  // ガンマ補正
        const v = corrected * @as(f32, @floatFromInt(pwm_period));
        out[i] = @intFromFloat(@max(0.0, @min(@as(f32, @floatFromInt(pwm_period)), v)));
    }
    return out;
}

const breath_table: [table_len]u16 = buildBreathTable();
```

ポイント:

- `buildBreathTable()` の中で `@sin` / `std.math.pow` を呼んでいるが、 これらはすべて **ホスト (PC) 側の Zig コンパイラが** 実行する。 MCU 側のコードには浮動小数点の calc は 1 命令も出ない
- `@setEvalBranchQuota(200_000)` は「comptime での命令実行回数の上限」 を上げる指示。 `pow` 内部のループが多くてデフォルト 20,000 では足りないため
- 結果は `[256]u16` = 512 バイトの ROM 定数。 ループ側は `breath_table[idx]` でインデックス引きするだけ

### サイズ

最終 bin は **0.8KB**。 512 バイトのテーブルが入っているとは思えないコンパクトさ。 これは:

- ReleaseSmall のリンカが似たビットパターンを共通化している
- ガンマ補正済みのテーブルは「同じ値が連続する区間」 が多く、 デッドコードを含めても `.text` が短い

ことの合わせ技。

### 改変アイデア

- ガンマを 1.0 / 2.2 / 3.0 で切り替えて、 視覚的な呼吸感の違いを観察
- sin の代わりに「三角波」 や「ノコギリ波」 でテーブルを作って比較

---

## 4 つを通して見えてくる「Zig らしさ」

| 観点 | 言語機能 | 例 |
|---|---|---|
| **ランタイムを comptime に追い出す** | `comptime` 関数 / ブロック | A の符号化、 D の sin テーブル |
| **不正な状態を表現できないようにする** | `tagged union` + 網羅 switch、 `packed struct(uN)` | B のステート、 C の設定 |
| **数値の安全な操作** | `+\|=` (飽和)、 `@truncate` / `@intCast`、 ビット幅指定整数 | B のスコア、 C の各フィールド |
| **OS なし環境の特性を活かす** | `freestanding` でも `comptime` + `std.math` は使える | A / D は std を import しているが OS 機能には触らない |

第13章では「使える / 使えない」 を表で整理した。 本章はそれを **動く 4 つのコード** で裏付けたもの、 と捉えると章間の繋がりが分かりやすい。

---

## 使い方

```sh
zig build -Dexample=compile_time_morse flash
zig build -Dexample=state_machine_game flash    # OLED + ボタン (PD1) が必要
zig build -Dexample=packed_settings flash       # LED + ボタン
zig build -Dexample=comptime_lookup flash       # PWM LED (PD2 = TIM1_CH1)
```

それぞれの配線は各 `examples/<name>/main.zig` の冒頭コメントに書いてある。

---

## まとめ

- `comptime` を使うと、 計算結果 (配列 / テーブル / 文字列展開) が ROM の `.rodata` に焼かれ、 実機の RAM/CPU を消費しない
- `tagged union` + 網羅 switch でステートマシンを書くと、 「ステートを増やすたびにハンドラの抜けが compile error で見つかる」 という安全な拡張ができる
- `packed struct(uN)` + `@bitCast` + `@compileError` の組み合わせで、 「永続化したい設定を 1 ワードに収める」 ような場面が表現的に書ける
- これらは ARM Cortex-M でも RISC-V でも同じように使えるので、 ターゲットを変えても再利用可能なパターン
