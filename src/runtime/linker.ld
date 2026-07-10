/*
 * FLASH を 2 つに分ける:
 *  - FLASH      : コード + .rodata + .data の LMA  (16K - 64B)
 *  - USER_DATA  : ファームウェアが書き換える永続データ用 (64B = 1 ページ)
 * これにより、リンカが .text の溢れと user データ領域の衝突を検出できる。
 */
MEMORY
{
    FLASH     (rx)  : ORIGIN = 0x08000000, LENGTH = 16K - 64
    USER_DATA (r)   : ORIGIN = 0x08003FC0, LENGTH = 64
    RAM       (rwx) : ORIGIN = 0x20000000, LENGTH = 2K
}

SECTIONS
{
    .vector_table :
    {
        . = ALIGN(4);
        KEEP(*(.vector_table))
        . = ALIGN(4);
    } > FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > FLASH

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > FLASH

    _sidata = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    PROVIDE(__global_pointer$ = ORIGIN(RAM) + 0x800);
    PROVIDE(_stack_top = ORIGIN(RAM) + LENGTH(RAM));

    /* ユーザデータページ (永続化用) のアドレスを HAL に露出 */
    PROVIDE(_user_data_start = ORIGIN(USER_DATA));
    PROVIDE(_user_data_size  = LENGTH(USER_DATA));

    /DISCARD/ :
    {
        *(.eh_frame*)
        *(.comment)
        *(.note*)
    }
}
