# ch32fun_zig (CH32V003)

`ch32fun` の開発体験を、Zig ネイティブで使えるようにした CH32V003 向けの軽量環境です。  
GPIO / SysTick / I2C / SSD1306 を使ったファームウェアを、`zig build` だけでビルド・書き込みできます。

English version: [README.md](README.md)

## 特徴

- CH32V003 向けの pure Zig 実装
- `zig build -Dexample=<name>` でサンプル切り替え
- `zig build ... flash` で Zig 製 WCH-LinkE 専用ツールによる書き込み
- SSD1306 (I2C) とボタン入力のサンプルを同梱

## 動作環境

- Zig `0.17.0`（確認済み: `0.17.0`）
- WCH-LinkE（RISC-V モード）と実行時の libusb 1.0（書き込み時）
- Linux/macOS のシェル環境（`sh`）
- 任意（`disasm` / `mapfile` / `size` を使う場合のみ）:
  - `llvm-objdump` / `llvm-nm` / `llvm-size`、または
  - `riscv-none-elf-objdump` / `riscv-none-elf-nm` / `riscv-none-elf-size`

## 依存のインストール

### macOS（Homebrew）

```sh
# Zig 0.17
brew install zig            # Homebrew がまだ 0.17 を提供していない場合は
                            # 後述の tarball インストールを使ってください

# LLVM ツール群（任意。disasm / mapfile / size を使う場合のみ）
brew install llvm
# brew の llvm を PATH に通す
echo 'export PATH="$(brew --prefix llvm)/bin:$PATH"' >> ~/.zshrc

# WCH-LinkE 専用ツールの USB 通信に libusb が必要
brew install libusb
```

### Linux（Debian / Ubuntu）

```sh
# WCH-LinkE 専用ツールの実行時に libusb が必要
sudo apt update
sudo apt install -y libusb-1.0-0

# LLVM ツール群（任意。disasm / mapfile / size を使う場合のみ）
sudo apt install -y llvm
```

### Linux（Arch）

```sh
sudo pacman -S --needed libusb llvm
```

### 公式 tarball から Zig 0.17 を入れる（Mac/Linux）

パッケージマネージャに `0.17.0` がまだ無い場合は、
[ziglang.org/download](https://ziglang.org/download/) から直接取得します。

```sh
# macOS (Apple Silicon)
curl -LO https://ziglang.org/download/0.17.0/zig-aarch64-macos-0.17.0.tar.xz
tar -xJf zig-aarch64-macos-0.17.0.tar.xz
sudo mv zig-aarch64-macos-0.17.0 /usr/local/zig-0.17.0
sudo ln -sf /usr/local/zig-0.17.0/zig /usr/local/bin/zig

# Linux (x86_64)
curl -LO https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz
tar -xJf zig-x86_64-linux-0.17.0.tar.xz
sudo mv zig-x86_64-linux-0.17.0 /usr/local/zig-0.17.0
sudo ln -sf /usr/local/zig-0.17.0/zig /usr/local/bin/zig
```

確認:

```sh
zig version   # 0.17.0 が表示されれば OK
```

## セットアップ

1. サンプルをビルドします。

```sh
zig build -Dexample=blinky
```

2. マイコンへ書き込みます。

```sh
zig build -Dexample=blinky flash
```

## サンプル一覧

- `blinky`
  - LED トグル（PD0）
- `gpio_input`
  - ボタン入力で LED 制御（PD3 ボタン、PD0 LED）
- `timer_irq`
  - SysTick カウンタで周期トグル（PD0）
- `oled`
  - SSD1306 に回転文字/画像と基本図形を表示
  - PD1 ボタンでアニメ速度切替
- `persistent_counter`
  - 起動回数を FLASH 末尾の予約ページ (64B) に保存
  - 電源を入れ直してもカウンタが残り、回数ぶん PD0 の LED が点滅
- `uart_hello`
  - USART1 (PD5, 115200 8N1) に 1 秒おきに `[I] hello ...` を送出
- `swio_log`
  - SWIOへ整形ログを出力し、`minichlink -T`で表示
- `led_fade`
  - TIM1_CH1 PWM で PD2 の LED を呼吸させる
- `tone_song`
  - パッシブブザー (PD4 = TIM2_CH1) で C ドレミファ...ドを再生
- `adc_meter`
  - ADC ch3 (PD2) を読み、 raw 値と mV 値を UART に送出
- `exti_button`
  - EXTI で PD1 立ち下がりを拾い、 ISR から PD0 をトグル。 メインは `wfi`
- `compile_time_morse`
  - 文字列を `comptime` でモールス符号に展開、 ランタイムは PD0 を点滅させるだけ
- `state_machine_game`
  - `tagged union` + 網羅 `switch` で書く SSD1306 ミニゲーム (ボタン PD1)
- `packed_settings`
  - `packed struct(u32)` の設定を `@bitCast` + Flash `Slot(T)` で永続化
- `comptime_lookup`
  - `comptime` で sin テーブルを `.rodata` に焼き、 PWM LED (PD2) で呼吸させる
- `hc_sr04`
  - HC-SR04 (`PD0` トリガー、`PD1` エコー) で距離を測り、USART1へmm単位で送出
- `ir_text`
  - 38kHz 赤外線LEDリンクで短い UTF-8 文字列を送受信する (TX `PD0`, 復調済みRX `PD1`)
- `register_blinky`
  - GPIO/time HAL を使わず、RCC / GPIOD / SysTick の MMIO レジスタ直接操作で `PD0` を点滅

## SWIOプリントデバッグ

`fun.swio_log`はC版ch32funのDebugPrintfと互換性があり、追加のUARTピンなしで
整形ログを出力できます。Debugビルドでは既定で有効です。16KBへ収めるため、
実用時は次のroot宣言でログを明示的に有効化したsmallを推奨します。
小型フォーマッタは整数の`{d}`・`{x}`、文字列の`{s}`、型に応じた`{}`を
サポートします。

```zig
pub const ch32fun_swio_log_enabled = true;

fun.swio_log.init();
fun.swio_log.waitForTerminal(); // 起動直後のログを確実に捕捉する場合
fun.swio_log.info("value={d} flags=0x{x}", .{ value, flags });
fun.swio_log.warn("waiting", .{});
fun.swio_log.err("failed code={d}", .{code});
```

ビルドして書き込んだ後、ターミナルを起動します。

```sh
zig build -Dexample=swio_log -Doptimize=small
zig build -Dexample=swio_log -Doptimize=small flash
minichlink -T # SWIO ターミナルを使う場合だけ別途インストール
```

root宣言がない`small`、`fast`、`safe`では`swio_log.enabled`が
コンパイル時に`false`となります。各ログ関数はno-opになり、フォーマット処理、
文字列、DMDATAアクセスは最終イメージから除去されます。明示宣言を`false`に
すれば、Debugビルドからログを除去することもできます。

```zig
if (fun.swio_log.enabled) fun.swio_log.info("debug only", .{});
```

ログ出力はブロッキング式です。ISRや赤外線通信など時間制約のある処理内では
使用しないでください。`waitForTerminal()`は`minichlink -T`が起動するまで処理を
進めません。また、ターミナル接続中はPD1がSWIOに占有されます。

## HC-SR04 サンプル配線

- HC-SR04 `TRIG` -> `PD0`
- HC-SR04 `ECHO` -> 抵抗分圧またはレベルシフター -> `PD1`
- HC-SR04 `VCC` -> `5V`
- HC-SR04 `GND` -> `GND`
- USBシリアル変換の RX -> `PD5`（115200bps、8N1）

HC-SR04 の ECHO は 5V ロジックです。CH32V003へ直接接続せず、抵抗分圧
またはレベルシフターで3.3V以下に落としてください。

## OLED サンプル配線

- OLED `SDA` -> `PC1`
- OLED `SCL` -> `PC2`
- OLED `VCC` / `GND` -> 電源
- ボタン -> `PD1`（内部プルアップ利用、押下で GND に落ちる想定）

注:
- I2C は `1MHz` Fast mode 設定です。
- SSD1306 I2C アドレスは `0x3C`、`0x3D` の順に自動検出します。
- SSD1306の画面サイズは既定で`128x64`です。`128x32`品ではアプリケーションのルートに`pub const ch32fun_ssd1306_panel_size = .@"128x32";`を宣言します。初期化、座標、フルバッファ容量、転送ページ数がまとめて切り替わります。

## SSD1306 描画ヘルパ

- `initPanelController(.ssd1306)` / `.ssd1309` / `.sh1106` で表示コントローラーを選択できます。
- SH1106 選択時は I2C を 400kHz に設定し、128x64パネル向け2列オフセットのページ転送を使用します。
- `initPanelWithOrientation(.portrait)` / `.landscape` / `.landscape_flip` / `.portrait_flip` で初期化時に論理画面の向きを指定できます。
- `logicalWidth()` / `logicalHeight()` で現在の論理座標サイズを取得できます（縦画面では `64x128`）。
- `drawStrRot` / `drawCharRot` / `drawImageRot` で `0/90/180/270` 回転表示ができます。
- `measureText` / `measureTextRot` で内蔵 8x8 フォントの文字列サイズを取得でき、中央寄せや右寄せに使えます。
- 既定値は従来どおり256文字のフルフォントです。容量を優先する場合はルートソースに `pub const ch32fun_ssd1306_basic_ascii_font = true;` を宣言すると、728バイトのASCII `0x20`〜`0x7A`だけを組み込みます。範囲外の文字は空白表示になります。
- 文字は `opaque_bg=false` で背景透過描画できます。
- 基本図形として `drawLine` / `drawRect` / `fillRect` / `drawCircle` / `fillCircle` / `drawRoundRect` / `fillRoundRect` / `drawHLine` / `drawVLine` を追加しています。
- 拡張ヘルパとして `drawLineThick` / `drawRectThick` / `drawCircleThick` / `drawRoundRectThick` / `drawFrame` / `drawRoundFrame` / `drawTriangle` / `fillTriangle` / `drawEllipse` / `fillEllipse` / `drawProgressBar` を追加しています。
- `drawBitmapMasked` で同形式の 1bpp マスク付きスプライト描画ができます。
- 既定のフルバッファ方式は128x64で1,024バイト、128x32で512バイトです。ルートソースへ `pub const ch32fun_ssd1306_buffer_mode = .page;` を宣言すると128バイトのページバッファになり、`firstPage()`から`nextPage()`がfalseになるまで同じ読み取り専用の画面を描画します。詳細は[SSD1306ページ描画](docs/ssd1306-page-rendering.md)を参照してください。

## ボタン入力ヘルパ

`fun.input.Button` で任意の GPIO ピンに接続したボタンを扱えます。

```zig
const a = fun.input.Button.init(.{
    .pin = fun.gpio.pin(.D, 1),
    .pull = .up,
    .active = .low,
});
const b = fun.input.button(.{
    .pin = fun.gpio.pin(.D, 3),
    .pull = .down,
    .active = .high,
});

if (a.isPressed() or b.isPressed()) {
    // ...
}
```

既存の `initButtonPd1Pullup()` / `isButtonPressed()` は、互換性のため
PD1 active-low のショートカットとして残しています。

## IR Text サンプル配線

- IR LED アノード -> 抵抗 -> `PD0`、カソード -> `GND`
- 38kHz 復調済み IR 受信モジュール `OUT` -> `PD1`
- ステータス LED -> `PD2`
- 受信モジュール `VCC` / `GND` -> モジュール仕様に合う電源

`fun.ir` は `IRText v1` フレームを使います。38kHz キャリア、NEC風の pulse-distance bit、`"IR"` magic、version、payload length、UTF-8 payload、Dallas/Maxim CRC-8 で構成されます。

CH32V003J4M6 で低ジッタのキャリアを使う場合は、ドライバを `PC4` に接続し、
`Tx.carrier_mode = .tim1_ch4_pc4` を指定します。`sendPacket32` /
`recvPacket32` では固定長のコンパクトな NEC 風フレームを送受信できます。
`sendFrame8` / `recvFrame8` では、アプリ側の64 bit演算なしで8バイトの
固定長フレームを送受信できます。

## よく使うコマンド

```sh
# サンプルをビルド（.elf / .bin / .hex を出力）
zig build -Dexample=oled

# 書き込み
zig build -Dexample=oled flash

# サイズ表示（llvm-size または riscv-none-elf-size が必要）
zig build -Dexample=oled size

# 逆アセンブル（llvm-objdump または riscv-none-elf-objdump が必要）
zig build -Dexample=oled disasm

# シンボルマップ（llvm-nm または riscv-none-elf-nm が必要）
zig build -Dexample=oled mapfile
```

## プロジェクト雛形の生成

この checkout から `chzig` ヘルパコマンドをインストールします。

```sh
sh tools/install-chzig.sh
```

その後、このパッケージに依存し、`@import("ch32fun")` から全 HAL
モジュールを使える新規プロジェクトを作成できます。

```sh
chzig init my_firmware
cd my_firmware
zig build
chzig flash
```

デフォルトでは `$HOME/.local/bin/chzig` にインストールします。別の場所へ
入れる場合は `sh tools/install-chzig.sh --prefix /path/to/prefix` を使います。
インストーラはこのリポジトリの Zig 製 WCH-LinkE ツールをビルドして同梱するため、
`chzig flash` で `zig-out/firmware/firmware.bin` をビルドして書き込めます。
ビルド後、`chzig flash` は書き込み前に FLASH と RAM の占有率を
パーセント付きのバーで表示します。FLASH はユーザーデータ用の最終64バイトを
除いた16,320バイトをアプリ領域として計算します。
書き込み後は各 64 バイトページを読み戻して検証します。

## 出力ファイル

デフォルトの `zig build` で `zig-out/firmware/` に以下が生成されます。

- `<example>.elf`
- `<example>.bin`
- `<example>.hex`

任意の生成物（対応するステップを明示的に実行した場合のみ）:

- `<example>.lst` — `zig build … disasm`
- `<example>.map` — `zig build … mapfile`

## ディレクトリ構成

- `src/`
  - HAL / レジスタ定義 / 起動コード
- `examples/`
  - 実行可能サンプル群
- `tools/flash.sh`
  - Zig 製ツールを呼び出す補助スクリプト
- `tools/wchlinke.zig`
  - WCH-LinkE 専用書き込みツール

## 制約

- 現在は CH32V003 を対象にしています。
- 書き込みツールは WCH-LinkE の RISC-V モードと CH32V003 のみ対応します。
- USB 通信には実行時 libusb 1.0 が必要です。
