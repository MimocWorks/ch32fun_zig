# トラブルシューティング

「ビルドはできたのに動かない」「書き込みで詰まる」 系の症状ごとのチェックポイント。

## ビルド系

### `zig build` で「Unknown example 'xxx'」

- `build.zig` の `examples` 配列に該当 example が登録されているか確認
- 名前のタイポ。`-Dexample=` の値はディレクトリ名と一致が必要

### `zig build disasm` / `mapfile` / `size` でコマンドが見つからない

- LLVM ツールが入っていないため。`brew install llvm` や `sudo apt install llvm` で導入
- もしくは GNU 系の `riscv-none-elf-*` をインストール (本プロジェクトの sh が両方フォールバックする)

### `zig version` が `0.16.0` でない

- README の手順に従って `0.16.0` を導入。Homebrew が `0.15.x` をインストールするケースは tarball で上書きする

## バイナリ生成系

### 16K に収まらない

- `zig build size` でセクションサイズを確認
- 多くの場合、`.text` 過大: 第 3 章で扱った `link_function_sections` / `link_gc_sections` が有効か確認
- `Feature.c` が外れていないか (圧縮命令が無いとサイズ倍増)

### ELF はできるが `.bin` が極端に大きい

- `.bin` は LMA 上のレンジを Raw に出すため、 「FLASH の途中にだけデータがある」と途中の隙間が全部 0 で埋められる
- 第 4 章のリンカスクリプトで `.data` を `> RAM AT > FLASH` にしているか確認 (`AT >` を書き忘れると FLASH に詰めない)

## 書き込み系

### `minichlink not found`

- `tools/flash.sh` は `../ch32fun/minichlink/minichlink` を見るので、 ディレクトリ配置と `make` 済みかを確認
- `which minichlink` が PATH 上にあるなら、スクリプトの `MINICHLINK` 行を書き換えても良い

### `libusb` 関連で `minichlink` のビルドが通らない

- macOS: `brew install libusb pkg-config`
- Debian/Ubuntu: `sudo apt install libusb-1.0-0-dev pkg-config`
- Arch: `sudo pacman -S libusb pkgconf`

### USB デバイスが見えない (Linux)

- `49-wch.rules` を `/etc/udev/rules.d/` に置いて `sudo udevadm control --reload-rules`
- ユーザを `plugdev` (Ubuntu) に追加して再ログイン
- `lsusb` で WCH のベンダ ID (`1a86`) が見えるか確認

### 書き込みに成功してもチップが動かない

1. LED 等の物理配線を見直す
2. `zig build disasm` で `.lst` を見て、 `_start` が `.vector_table` の先頭ワードが指している番地と一致しているか
3. `_start_c` の最後で `root.main()` を呼んでいるか
4. クロックが上がっていないと SysTick の `delayMs` の体感が極端に遅くなる: `system.init` を呼んでいるか確認

## 実行時の挙動が変

### 起動直後に固まる

- 多くは `mtvec` 設定前に割り込みが入って `_default_irq_entry` で `wfi` ループ
- `_start_c` の `setupMachineState()` の順序を確認
- `Feature.e` が外れたまま (= RV32I のレジスタ x16+ を出力するコードが走る) 可能性も。 ターゲット設定を再確認

### `.data` のグローバルが期待値で初期化されない

- `copyData()` が呼ばれているか
- リンカスクリプトの `_sidata = LOADADDR(.data);` 行があるか (これが無いと FLASH 上のロードアドレスが解決できない)

### ボタンが反応しない

- `gpio.enablePortClock(.D)` 呼んでいるか
- 配線が GND プルダウンになっていないか (本プロジェクトはアクティブ Low + 内部プルアップ前提)

## I2C / SSD1306 系

### `initI2c` が `BusyTimeout` で帰ってくる

- SDA/SCL に **外部プルアップ抵抗** (4.7k〜10kΩ) があるか確認。 内部プルアップに頼ると Fast mode 1MHz では持たない
- バスに何も繋がっていなくても `STAR2.BUSY` は基本下りるはず。 立ちっぱなしならハード起因 (配線 / 電源)

### 画面が真っ黒のまま

- I2C アドレス (`0x3C`) が個体と一致しているか
- `setbuf(false) → refresh()` の順で 1 度書いてみて、何も出なければハード側
- `oled` サンプルから流用して動作確認するのが手っ取り早い
