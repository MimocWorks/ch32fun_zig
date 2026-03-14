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

- Zig `0.15.x`（確認済み: `0.15.2`）
- `../ch32fun/minichlink/minichlink`
- Linux/macOS のシェル環境（`sh`）
- 任意: `llvm-objdump` / `llvm-nm`（なければ `riscv-none-elf-*` にフォールバック）

## セットアップ

1. `ch32fun` 側の `minichlink` をビルドします。

```sh
make -C ../ch32fun/minichlink
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
# サンプルをビルド
zig build -Dexample=oled

# サイズ表示
zig build -Dexample=oled size

# 書き込み
zig build -Dexample=oled flash
```

## 出力ファイル

生成物は `zig-out/firmware/` に出力されます。

- `<example>.elf`
- `<example>.bin`
- `<example>.hex`
- `<example>.lst`
- `<example>.map`

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
