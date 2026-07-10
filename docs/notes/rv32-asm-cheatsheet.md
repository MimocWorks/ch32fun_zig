# RV32 アセンブリ チートシート

本書の起動コードやベクタテーブル章で出てきた RV32 命令の要点まとめ。

## レジスタ別名

| ABI 名 | 物理 | 用途 |
|---|---|---|
| `zero` | x0 | 常に 0 |
| `ra` | x1 | リターンアドレス |
| `sp` | x2 | スタックポインタ |
| `gp` | x3 | グローバルポインタ (Linker Relaxation で使用) |
| `tp` | x4 | スレッドポインタ |
| `t0`〜`t2` | x5〜x7 | 一時 (caller-saved) |
| `s0`〜`s1` | x8〜x9 | 保存 (callee-saved) — RV32E では x8 までしか無いので注意 |
| `a0`〜`a7` | x10〜x17 | 引数・戻り値 — **RV32E では a0〜a5 (x10〜x15) まで** |
| `s2`〜`s11` | x18〜x27 | 保存 — RV32E には無い |
| `t3`〜`t6` | x28〜x31 | 一時 — RV32E には無い |

> ⚠️ RV32E は `x0`〜`x15` までしか持たない。 本書の SysTick ハンドラの退避コードに `s2`〜`s11` / `t3`〜`t6` が並んでいるのは、 RVE であっても LLVM の RISC-V バックエンドが安全側に倒して命令を出すので、 ハンドラ側も対応して退避している、という事情。

## よく出てきた命令

| 命令 | 意味 |
|---|---|
| `la rd, sym` | `rd ← &sym`。擬似命令で `auipc + addi` に展開 |
| `li rd, imm` | `rd ← imm`。擬似命令で `lui + addi` などに展開 |
| `j label` | `PC ← label` (無条件ジャンプ) |
| `call sym` | `ra ← PC+4; PC ← sym` |
| `addi rd, rs, imm` | `rd ← rs + imm` |
| `sw rs, offset(rs1)` | `MEM[rs1+offset] ← rs` (4 バイト書き込み) |
| `lw rd, offset(rs1)` | `rd ← MEM[rs1+offset]` (4 バイト読み出し) |
| `csrw csr, rs` | `csr ← rs` |
| `csrs csr, rs` | `csr ← csr | rs` |
| `csrci csr, imm` | `csr ← csr & ~imm5` |
| `mret` | 機械モード trap からの復帰。`mstatus.MIE` を `MPIE` で復元、`PC ← mepc` |
| `wfi` | 割り込みが来るまで停止 |

## 起動 asm の意味の取り方

```asm
.option push
.option norelax
la gp, __global_pointer$
.option pop
```

- `la gp, __global_pointer$` は通常 `auipc + addi` に展開され、 さらに RISC-V リンカは `gp` 相対の命令に "relax" する。
- ところが `gp` 自身の値を `gp` 相対で求めるのは無意味。 そこで `.option norelax` で囲い、`auipc + addi` の素の展開を保つ。

```asm
la sp, _stack_top
j _start_c
```

- スタックを RAM 末尾に立てる。
- `_start_c` には `j` で飛ぶ — 戻る必要がないので `call` (= `ra` を積む) より軽い。

## SysTick ハンドラの caller-saved 退避

```asm
addi sp, sp, -128
sw ra, 124(sp)
sw gp, 120(sp)
sw tp, 116(sp)
sw t0, 112(sp)
...
sw t6, 8(sp)
call _systick_irq_body
lw t6, 8(sp)
...
addi sp, sp, 128
mret
```

- `sp` を 128 バイト下に降ろし、32 個 (4 バイト × 32 = 128) のレジスタ分の枠を確保。
- `ra` と `gp`/`tp` も含めて退避するのは、`mret` 後の戻り先と Linker Relaxation 用ベースを守るため。
- `mret` で `PC ← mepc`、 `mstatus.MIE ← mstatus.MPIE` が同時に行われ、 元のコンテキストへ戻る。
