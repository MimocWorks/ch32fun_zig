# CH32V003 レジスタ早見表

`src/periph/registers.zig` で扱っている主要ベース番地とオフセットの要約。 データシートの該当章を引くときの索引として使う。

## メモリマップ全体

| 領域 | 番地レンジ |
|---|---|
| Boot alias (BOOT0 で FLASH / BootROM にエイリアス) | `0x0000_0000`〜`0x0000_3FFF` (16 KB) |
| 予約 | `0x0000_4000`〜`0x07FF_FFFF` |
| FLASH | `0x0800_0000`〜`0x0800_3FFF` (16 KB) |
| 予約 | `0x0800_4000`〜`0x1FFF_EFFF` |
| System Memory (BootROM, USART ISP) | `0x1FFF_F000`〜`0x1FFF_F7FF` (1.92 KB) |
| Factory trim (HSI 校正値などの工場 ROM) | `0x1FFF_F7D4` ほか |
| Option bytes (RDPR / USER) | `0x1FFF_F800`〜`0x1FFF_F80F` |
| 予約 | `0x1FFF_F810`〜`0x1FFF_FFFF` |
| SRAM  | `0x2000_0000`〜`0x2000_07FF` (2 KB) |
| 予約 | `0x2000_0800`〜`0x3FFF_FFFF` |
| 周辺 (APB1/APB2/AHB) | `0x4000_0000`〜`0x5FFF_FFFF` |
| 予約 | `0x6000_0000`〜`0xDFFF_FFFF` |
| コア内蔵周辺 (PFIC, SysTick, ...) | `0xE000_0000`〜`0xFFFF_FFFF` |

> リセット直後の CPU は `PC = 0x0000_0000` から fetch するが、 ハードウェアが BOOT0 ピンの状態に応じて `0x0800_0000` (FLASH) または `0x1FFF_F000` (BootROM) に透過的にエイリアスする。 ソフトから見たアドレスは最初から `0x0800_xxxx` 系。

## バスごとのベース

| バス | ベース | 主な乗物 |
|---|---|---|
| APB1 | `0x4000_0000` | TIM2, I2C1, USART1 など |
| APB2 | `0x4001_0000` | AFIO, GPIOA/C/D, EXTI, TIM1, ADC1 など |
| AHB  | `0x4002_0000` | RCC, FLASH 制御, DMA, CRC など |

## 個別ペリフェラル

| 名前 | ベース | 主なオフセット |
|---|---|---|
| RCC      | `0x4002_1000` | `CTLR=+0x00`, `CFGR0=+0x04`, `APB2PCENR=+0x18`, `APB1PCENR=+0x1C` |
| FLASH 制御 | `0x4002_2000` | `ACTLR=+0x00`, `KEYR=+0x04`, `OBKEYR=+0x08`, `STATR=+0x0C`, `CTLR=+0x10`, `ADDR=+0x14`, `OBR=+0x1C`, `WPR=+0x20`, `MODEKEYR=+0x24`, `BOOT_MODEKEYR=+0x28` |
| GPIOA    | `0x4001_0800` | `CFGLR=+0x00`, `INDR=+0x08`, `OUTDR=+0x0C`, `BSHR=+0x10` |
| GPIOC    | `0x4001_1000` | 同上 |
| GPIOD    | `0x4001_1400` | 同上 |
| I2C1     | `0x4000_5400` | `CTLR1=+0x00`, `CTLR2=+0x04`, `DATAR=+0x10`, `STAR1=+0x14`, `STAR2=+0x18`, `CKCFGR=+0x1C` |
| PFIC     | `0xE000_E000` | `ISR=+0x00`, `IENR=+0x100` 系 |
| SysTick  | `0xE000_F000` | `CTLR=+0x00`, `SR=+0x04`, `CNT=+0x08`, `CMP=+0x10` |

## 主要ビットマスク

### RCC.APB2PCENR

| ビット | 内容 |
|---|---|
| 0 | AFIO |
| 2 | GPIOA |
| 4 | GPIOC |
| 5 | GPIOD |

### RCC.APB1PCENR

| ビット | 内容 |
|---|---|
| 21 | I2C1 |

### I2C CTLR1

| 名前 | ビット |
|---|---|
| PE     | 0 |
| START  | 8 |
| STOP   | 9 |
| ACK    | 10 |

### SysTick CTLR

| 名前 | ビット |
|---|---|
| STE   | 0 |
| STIE  | 1 |
| STCLK | 2 |

### FLASH CTLR (書き込み用)

| 名前 | ビット |
|---|---|
| PG (FTPG)    | 0  |
| PER (FTER)   | 1  |
| STRT         | 6  |
| LOCK         | 7  |
| FAST_LOCK    | 15 |
| BUF_LOAD     | 18 |
| BUF_RST      | 19 |

### FLASH STATR

| 名前 | ビット |
|---|---|
| BSY         | 0 |
| WRPRTERR    | 4 |
| EOP         | 5 |

### FLASH KEYR / MODEKEYR シーケンス

`0x45670123 → 0xCDEF89AB` の順で 2 回書き込むと、 それぞれ主ロック / fast プログラムロックが外れる。
