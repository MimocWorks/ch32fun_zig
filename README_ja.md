# ch32fun_zig (CH32V003)

`ch32fun` の開発体験を、Zig ネイティブで使えるようにした CH32V003 向けの軽量環境です。  
GPIO / SysTick / I2C / SSD1306 を使ったファームウェアを、`zig build` だけでビルド・書き込みできます。

English version: [README.md](README.md)

## 特徴

- CH32V003 向けの pure Zig 実装
- `zig build -Dexample=<name>` でサンプル切り替え
- `zig build ... flash` で `minichlink` による書き込み
- SSD1306 (I2C) とボタン入力のサンプルを同梱

## 動作環境

- Zig `0.16.0`（確認済み: `0.16.0`）
- `../ch32fun/minichlink/minichlink`（`flash` 実行時に必要）
- Linux/macOS のシェル環境（`sh`, `make`）
- 任意（`disasm` / `mapfile` / `size` を使う場合のみ）:
  - `llvm-objdump` / `llvm-nm` / `llvm-size`、または
  - `riscv-none-elf-objdump` / `riscv-none-elf-nm` / `riscv-none-elf-size`

## 依存のインストール

### macOS（Homebrew）

```sh
# Zig 0.16
brew install zig            # Homebrew がまだ 0.16 を提供していない場合は
                            # 後述の tarball インストールを使ってください

# LLVM ツール群（任意。disasm / mapfile / size を使う場合のみ）
brew install llvm
# brew の llvm を PATH に通す
echo 'export PATH="$(brew --prefix llvm)/bin:$PATH"' >> ~/.zshrc

# minichlink のビルドに libusb が必要
brew install libusb pkg-config
```

### Linux（Debian / Ubuntu）

```sh
# minichlink ビルドに必要なツールチェインと libusb
sudo apt update
sudo apt install -y build-essential git pkg-config libusb-1.0-0-dev

# LLVM ツール群（任意。disasm / mapfile / size を使う場合のみ）
sudo apt install -y llvm
```

### Linux（Arch）

```sh
sudo pacman -S --needed base-devel git pkgconf libusb llvm
```

### 公式 tarball から Zig 0.16 を入れる（Mac/Linux）

パッケージマネージャに `0.16.0` がまだ無い場合は、
[ziglang.org/download](https://ziglang.org/download/) から直接取得します。

```sh
# macOS (Apple Silicon)
curl -LO https://ziglang.org/download/0.16.0/zig-macos-aarch64-0.16.0.tar.xz
tar -xJf zig-macos-aarch64-0.16.0.tar.xz
sudo mv zig-macos-aarch64-0.16.0 /usr/local/zig-0.16.0
sudo ln -sf /usr/local/zig-0.16.0/zig /usr/local/bin/zig

# Linux (x86_64)
curl -LO https://ziglang.org/download/0.16.0/zig-linux-x86_64-0.16.0.tar.xz
tar -xJf zig-linux-x86_64-0.16.0.tar.xz
sudo mv zig-linux-x86_64-0.16.0 /usr/local/zig-0.16.0
sudo ln -sf /usr/local/zig-0.16.0/zig /usr/local/bin/zig
```

確認:

```sh
zig version   # 0.16.0 が表示されれば OK
```

## セットアップ

1. このリポジトリと同じ階層に `ch32fun` を clone し、`minichlink` をビルドします。

```sh
# build.zig が想定するディレクトリ配置
# .
# ├── ch32fun/
# └── ch32fun_zig/   <-- 今ここ

cd ..
git clone https://github.com/cnlohr/ch32fun.git
make -C ch32fun/minichlink
cd ch32fun_zig
```

2. サンプルをビルドします。

```sh
zig build -Dexample=blinky
```

3. マイコンへ書き込みます。

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

## OLED サンプル配線

- OLED `SDA` -> `PC1`
- OLED `SCL` -> `PC2`
- OLED `VCC` / `GND` -> 電源
- ボタン -> `PD1`（内部プルアップ利用、押下で GND に落ちる想定）

注:
- I2C は `1MHz` Fast mode 設定です。
- SSD1306 I2C アドレスは `0x3C` 前提です。

## SSD1306 描画ヘルパ

- `drawStrRot` / `drawCharRot` / `drawImageRot` で `0/90/180/270` 回転表示ができます。
- `measureText` / `measureTextRot` で内蔵 8x8 フォントの文字列サイズを取得でき、中央寄せや右寄せに使えます。
- 文字は `opaque_bg=false` で背景透過描画できます。
- 基本図形として `drawLine` / `drawRect` / `fillRect` / `drawCircle` / `fillCircle` / `drawRoundRect` / `fillRoundRect` / `drawHLine` / `drawVLine` を追加しています。
- `drawBitmapMasked` で同形式の 1bpp マスク付きスプライト描画ができます。
- 実装は 1024 バイトの単一フレームバッファを維持し、回転用の追加バッファは持ちません。

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
  - `minichlink` を呼び出す書き込みスクリプト

## 制約

- 現在は CH32V003 を対象にしています。
- `flash` ターゲットは `../ch32fun/minichlink/minichlink` の存在を前提にしています。
