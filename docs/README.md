# ch32fun_zig 技術ドキュメント

本プロジェクト `ch32fun_zig` が、 どのようにして **追加の RISC-V ツールチェイン無しで CH32V003 (RV32EC) 向けファームウェアをビルド・書き込みできているのか** を、コードベースに沿って解剖した技術書。

## 対象読者

- C/C++ で組み込み開発の経験があり、 リンカスクリプトや objcopy の概念は知っている
- Zig の基本構文と `build.zig` を一度くらい触ったことがある
- RISC-V については「ARM とは別 ISA」程度の認識でも読める

## ハイライト

- Zig 0.16 + LLVM の `Target.Query` で **RV32EC** をどう表現するか
- `linker.ld` の `> RAM AT > FLASH` トリック
- `_start` (naked) → `_start_c` の起動シーケンス
- `build.zig` のステップ DAG と `addObjCopy` の役割
- `minichlink` + SWIO による書き込み経路
- レジスタ層 / GPIO HAL / SysTick / I2C / SSD1306 の薄い積み重ね

## 構成

- `chapters/` — 章ごとのソース (Markdown)
- `notes/` — 用語集 / 早見表 / トラブルシューティング
- `generate-book.py` — 章群を 1 冊の PDF にまとめるスクリプト
- `ch32fun-zig-tutorial.pdf` — 生成済み PDF (生成後に出力される)

## PDF の生成

```sh
python3 -m venv /tmp/ch32pdfgen
/tmp/ch32pdfgen/bin/python -m pip install markdown weasyprint pygments
/tmp/ch32pdfgen/bin/python docs/generate-book.py
```

WeasyPrint は内部で pango / cairo を使う。 macOS なら `brew install pango`、 Linux なら `apt install libpango-1.0-0 libpangoft2-1.0-0` などが別途必要になる場合がある。

## 章一覧

### 第 I 部 — ターゲットとツールチェイン

- 第 1 章: 本書の対象とゴール
- 第 2 章: RV32EC というターゲットを正しく指定する
- 第 3 章: Zig 0.16 のクロスコンパイル基盤

### 第 II 部 — リンクと起動

- 第 4 章: メモリマップとリンカスクリプト
- 第 5 章: 起動コードとランタイム初期化
- 第 6 章: ベクタテーブルと割り込みエントリ

### 第 III 部 — ビルドパイプラインと書き込み

- 第 7 章: `build.zig` をひと通り歩く
- 第 8 章: ELF から `.bin` / `.hex` への変換
- 第 9 章: minichlink で実機に書き込む

### 第 IV 部 — HAL の構造

- 第 10 章: MMIO とレジスタ抽象化
- 第 11 章: HAL — GPIO と SysTick
- 第 12 章: HAL — I2C と SSD1306

### 第 V 部 — 言語仕様と標準ライブラリ

- 第 13 章: 本プロジェクトで使える Zig 言語機能と std

### 第 VI 部 — 永続化

- 第 14 章: データの永続化 — 内蔵 FLASH に書く HAL

### 第 VII 部 — 便利な周辺機能

- 第 15 章: 周辺機能の HAL — UART / log / PWM / Tone / ADC / EXTI

### 第 VIII 部 — Zig 言語機能を活かす

- 第 16 章: Zig 言語機能を活かしたファームウェアパターン

### 付録

- 付録 A: 用語集
- 付録 B: RV32 アセンブリ チートシート
- 付録 C: CH32V003 レジスタ早見表
- 付録 D: トラブルシューティング
