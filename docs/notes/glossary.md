# 用語集

本書で繰り返し登場する用語の要約集。

| 用語 | 説明 |
|---|---|
| **CH32V003** | WCH 製の RISC-V (RV32EC) MCU。FLASH 16KB / SRAM 2KB / 48MHz。本書のターゲット。 |
| **RV32E** | RISC-V 32-bit の組み込み派生。汎用レジスタが `x0`〜`x15` の 16 本に削られた版。 |
| **RV32EC** | RV32E + 圧縮命令 (C) 拡張。CH32V003 が採用。 |
| **C 拡張 (RVC)** | 16-bit 幅の短縮命令を導入する RISC-V 拡張。コード密度に効く。 |
| **freestanding** | OS が無い環境向けターゲット。libc などの標準ランタイムを前提にしない。 |
| **EABI** | Embedded ABI。組み込み向けの呼び出し規約。 |
| **MMIO** | Memory-Mapped I/O。周辺レジスタを物理メモリ番地経由で読み書きする方式。 |
| **MTVEC** | RISC-V の機械モード trap vector。割り込み / 例外発生時の PC 飛び先。 |
| **PFIC** | CH32V (QingKe) の Programmable Fast Interrupt Controller。NVIC 風の割り込みコントローラ。 |
| **SWIO** | CH32V のデバッグ / 書き込み用 1-wire シリアル。SWD 相当。 |
| **WCH-LinkE** | WCH 公式の SWIO ホストアダプタ。 |
| **minichlink** | ch32fun 同梱の USB-SWIO ブリッジ CLI。`-w <file>` で書き込み。 |
| **objcopy** | ELF を `.bin` / `.hex` に変換するツール。Zig の `addObjCopy` が同等処理を内包。 |
| **LMA / VMA** | リンカ用語。Load Memory Address は「書き込み先」、Virtual Memory Address は「実行時アドレス」。 |
| **`extern struct`** | C ABI 互換のメモリレイアウトを保証する Zig の構造体宣言。 |
| **`*volatile T`** | volatile な型付きポインタ。最適化で読み書きが省略・並び替えされない。 |
| **`compiler_rt`** | 乗除算ヘルパなど、CPU が持たない算術を補う関数群。Zig は自前実装を持つ。 |
| **lld** | LLVM 系のリンカ。Zig に同梱され、GNU `ld` を使わずにリンクが完結する。 |
| **PFIC IENR** | PFIC の Interrupt Enable Register。IRQ 番号ごとにビットを立てて有効化する。 |
| **SysTick** | コア標準の周期タイマ。`delayMs` / `systick.init` が使う。 |
| **SSD1306** | 128×64 OLED コントローラ。I2C 経由で叩く。 |
| **GDDRAM** | SSD1306 内部のグラフィクス用 DRAM。1024 バイトのフレームバッファそのもの。 |
