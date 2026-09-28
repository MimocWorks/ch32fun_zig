# Chapter 09: WCH-LinkE で実機に書き込む

この章では CH32V003 の `.bin` を WCH-LinkE 経由で内蔵 FLASH に書き込む経路を説明します。

## 構成

```text
zig build flash
  ├─ Zig でファームウェアをビルドし、.bin を生成
  ├─ Zig で tools/wchlinke.zig をホスト向けにビルド
  └─ wchlinke <firmware.bin>
       └─ libusb 1.0 → WCH-LinkE → SWIO → CH32V003
```

書き込みツールのソースはこのリポジトリ内にあり、minichlink の実行ファイルや
ch32fun の checkout は必要ありません。USB の bulk 転送には実行時の libusb 1.0 を
利用します。macOS は `brew install libusb`、Debian/Ubuntu は
`sudo apt install libusb-1.0-0` で導入できます。

## 書き込み

WCH-LinkE を RISC-V モードで接続し、SWIO と GND を対象ボードにつなぎます。

```sh
zig build -Dexample=blinky flash
```

`chzig` で作成したプロジェクトなら `chzig flash` を使います。単独の `.bin` を
書き込む場合は `zig-out/bin/wchlinke path/to/firmware.bin` を実行できます。

ツールは USB VID/PID `1a86:8010` の WCH-LinkE を開き、WCH の DMI コマンドで
対象を停止します。CH32V003 以外の応答は受け付けません。FLASH のロックを
解除し、64 バイトページごとに消去、書き込み、読み戻し検証を行います。
最後に対象をリセットします。ファームウェア用の最大サイズは、末尾のユーザー
データページを除く 16,320 バイトです。

書き込み中に USB 通信、FLASH ステータス、読み戻しのいずれかが失敗すると
非ゼロ終了します。書き込み済みページがある場合はその時点までの内容が残るので、
接続を確認して再実行してください。

## 対応範囲

- WCH-LinkE の RISC-V モード
- CH32V003 の内蔵 FLASH への `.bin` 書き込み
- macOS / Linux の libusb 1.0

SWIO ログのターミナルや、オプションバイト操作はこのツールの対象外です。
SWIO ログを使う場合は、別途ターミナルを用意してください。
