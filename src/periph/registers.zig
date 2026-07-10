pub const FLASH_BASE: usize = 0x08000000;
pub const SRAM_BASE: usize = 0x20000000;
pub const PERIPH_BASE: usize = 0x40000000;
pub const CORE_PERIPH_BASE: usize = 0xE0000000;

pub const APB2PERIPH_BASE: usize = PERIPH_BASE + 0x10000;
pub const APB1PERIPH_BASE: usize = PERIPH_BASE;
pub const AHBPERIPH_BASE: usize = PERIPH_BASE + 0x20000;

pub const GPIOA_BASE: usize = APB2PERIPH_BASE + 0x0800;
pub const GPIOC_BASE: usize = APB2PERIPH_BASE + 0x1000;
pub const GPIOD_BASE: usize = APB2PERIPH_BASE + 0x1400;
pub const I2C1_BASE: usize = APB1PERIPH_BASE + 0x5400;

pub const AFIO_BASE: usize = APB2PERIPH_BASE + 0x0000;
pub const EXTI_BASE: usize = APB2PERIPH_BASE + 0x0400;
pub const ADC1_BASE: usize = APB2PERIPH_BASE + 0x2400;
pub const TIM1_BASE: usize = APB2PERIPH_BASE + 0x2C00;
pub const USART1_BASE: usize = APB2PERIPH_BASE + 0x3800;
pub const SPI1_BASE: usize = APB2PERIPH_BASE + 0x3000;
pub const TIM2_BASE: usize = APB1PERIPH_BASE + 0x0000;
pub const DMA1_BASE: usize = AHBPERIPH_BASE + 0x0000;

pub const RCC_BASE: usize = AHBPERIPH_BASE + 0x1000;
pub const FLASH_R_BASE: usize = AHBPERIPH_BASE + 0x2000;

pub const PFIC_BASE: usize = CORE_PERIPH_BASE + 0xE000;
pub const SYSTICK_BASE: usize = CORE_PERIPH_BASE + 0xF000;

pub const CFG0_PLL_TRIM: usize = 0x1FFFF7D4;

pub const SYSTICK_CTLR_STE: u32 = 1 << 0;
pub const SYSTICK_CTLR_STIE: u32 = 1 << 1;
pub const SYSTICK_CTLR_STCLK: u32 = 1 << 2;

pub const RCC_APB2_AFIO: u32 = 0x00000001;
pub const RCC_APB2_GPIOA: u32 = 0x00000004;
pub const RCC_APB2_GPIOC: u32 = 0x00000010;
pub const RCC_APB2_GPIOD: u32 = 0x00000020;
pub const RCC_APB2_ADC1: u32 = 0x00000200;
pub const RCC_APB2_TIM1: u32 = 0x00000800;
pub const RCC_APB2_SPI1: u32 = 0x00001000;
pub const RCC_APB2_USART1: u32 = 0x00004000;
pub const RCC_APB1_TIM2: u32 = 0x00000001;
pub const RCC_APB1_I2C1: u32 = 0x00200000;
pub const RCC_AHB_DMA1: u32 = 0x00000001;

pub const I2C_CTLR1_PE: u16 = 0x0001;
pub const I2C_CTLR1_START: u16 = 0x0100;
pub const I2C_CTLR1_STOP: u16 = 0x0200;
pub const I2C_CTLR1_ACK: u16 = 0x0400;

pub const I2C_CTLR2_FREQ: u16 = 0x003F;

pub const I2C_STAR1_TXE: u16 = 0x0080;
pub const I2C_STAR2_BUSY: u16 = 0x0002;

pub const I2C_CKCFGR_CCR: u16 = 0x0FFF;
pub const I2C_CKCFGR_DUTY: u16 = 0x4000;
pub const I2C_CKCFGR_FS: u16 = 0x8000;

pub const FLASH_ACTLR_LATENCY_MASK: u32 = 0x3;
pub const FLASH_ACTLR_LATENCY_1: u32 = 0x1;

// Flash unlock keys (TRM)
pub const FLASH_KEY1: u32 = 0x45670123;
pub const FLASH_KEY2: u32 = 0xCDEF89AB;

// Flash CTLR bits
pub const FLASH_CTLR_PG: u32 = 1 << 0; // synonym FTPG (fast program)
pub const FLASH_CTLR_PER: u32 = 1 << 1; // synonym FTER (fast erase)
pub const FLASH_CTLR_STRT: u32 = 1 << 6;
pub const FLASH_CTLR_LOCK: u32 = 1 << 7;
pub const FLASH_CTLR_FAST_LOCK: u32 = 1 << 15;
pub const FLASH_CTLR_BUF_LOAD: u32 = 1 << 18;
pub const FLASH_CTLR_BUF_RST: u32 = 1 << 19;

// Flash STATR bits
pub const FLASH_STATR_BSY: u32 = 1 << 0;
pub const FLASH_STATR_WRPRTERR: u32 = 1 << 4;
pub const FLASH_STATR_EOP: u32 = 1 << 5;

pub const RccRegs = extern struct {
    CTLR: u32,
    CFGR0: u32,
    INTR: u32,
    APB2PRSTR: u32,
    APB1PRSTR: u32,
    AHBPCENR: u32,
    APB2PCENR: u32,
    APB1PCENR: u32,
    RESERVED0: u32,
    RSTSCKR: u32,
};

pub const FlashRegs = extern struct {
    ACTLR: u32,
    KEYR: u32,
    OBKEYR: u32,
    STATR: u32,
    CTLR: u32,
    ADDR: u32,
    RESERVED0: u32,
    OBR: u32,
    WPR: u32,
    MODEKEYR: u32,
    BOOT_MODEKEYR: u32,
};

pub const GpioRegs = extern struct {
    CFGLR: u32,
    CFGHR: u32,
    INDR: u32,
    OUTDR: u32,
    BSHR: u32,
    BCR: u32,
    LCKR: u32,
};

pub const SysTickRegs = extern struct {
    CTLR: u32,
    SR: u32,
    CNT: u32,
    RESERVED0: u32,
    CMP: u32,
    RESERVED1: u32,
};

pub const UsartRegs = extern struct {
    STATR: u32,
    DATAR: u32,
    BRR: u32,
    CTLR1: u32,
    CTLR2: u32,
    CTLR3: u32,
    GPR: u32,
};

pub const USART_STATR_TXE: u32 = 1 << 7;
pub const USART_STATR_TC: u32 = 1 << 6;
pub const USART_CTLR1_RE: u32 = 1 << 2;
pub const USART_CTLR1_TE: u32 = 1 << 3;
pub const USART_CTLR1_UE: u32 = 1 << 13;

pub const TimRegs = extern struct {
    CTLR1: u16,
    RESERVED0: u16,
    CTLR2: u16,
    RESERVED1: u16,
    SMCFGR: u16,
    RESERVED2: u16,
    DMAINTENR: u16,
    RESERVED3: u16,
    INTFR: u16,
    RESERVED4: u16,
    SWEVGR: u16,
    RESERVED5: u16,
    CHCTLR1: u16,
    RESERVED6: u16,
    CHCTLR2: u16,
    RESERVED7: u16,
    CCER: u16,
    RESERVED8: u16,
    CNT: u16,
    RESERVED9: u16,
    PSC: u16,
    RESERVED10: u16,
    ATRLR: u16,
    RESERVED11: u16,
    RPTCR: u16,
    RESERVED12: u16,
    CH1CVR: u32,
    CH2CVR: u32,
    CH3CVR: u32,
    CH4CVR: u32,
    BDTR: u16,
    RESERVED13: u16,
    DMACFGR: u16,
    RESERVED14: u16,
    DMAADR: u16,
    RESERVED15: u16,
};

pub const TIM_CTLR1_CEN: u16 = 1 << 0;
pub const TIM_CTLR1_ARPE: u16 = 1 << 7;
pub const TIM_BDTR_MOE: u16 = 1 << 15;
pub const TIM_CCER_CC1E: u16 = 1 << 0;
pub const TIM_CCER_CC2E: u16 = 1 << 4;
pub const TIM_CCER_CC3E: u16 = 1 << 8;
pub const TIM_CCER_CC4E: u16 = 1 << 12;
// CHxCTL: モード 6 (PWM1) を OCxM[2:0]=110 にセット + 出力プリロード有効 (OCxPE)
pub const TIM_CHCTLR_OC_PWM1_PRELOAD: u16 = (6 << 4) | (1 << 3);
pub const TIM_CHCTLR_OC_PWM1_PRELOAD_HI: u16 = ((6 << 4) | (1 << 3)) << 8;

pub const AdcRegs = extern struct {
    STATR: u32,
    CTLR1: u32,
    CTLR2: u32,
    SAMPTR1: u32,
    SAMPTR2: u32,
    IOFR1: u32,
    IOFR2: u32,
    IOFR3: u32,
    IOFR4: u32,
    WDHTR: u32,
    WDLTR: u32,
    RSQR1: u32,
    RSQR2: u32,
    RSQR3: u32,
    ISQR: u32,
    IDATAR1: u32,
    IDATAR2: u32,
    IDATAR3: u32,
    IDATAR4: u32,
    RDATAR: u32,
    DLYR: u32,
};

pub const ADC_CTLR2_ADON: u32 = 1 << 0;
pub const ADC_CTLR2_CAL: u32 = 1 << 2;
pub const ADC_CTLR2_RSTCAL: u32 = 1 << 3;
pub const ADC_CTLR2_SWSTART: u32 = 1 << 22;
pub const ADC_CTLR2_EXTSEL_SWSTART: u32 = 0b111 << 17;
pub const ADC_CTLR2_EXTTRIG: u32 = 1 << 20;
pub const ADC_STATR_EOC: u32 = 1 << 1;

pub const ExtiRegs = extern struct {
    INTENR: u32,
    EVENR: u32,
    RTENR: u32,
    FTENR: u32,
    SWIEVR: u32,
    INTFR: u32,
};

pub const AfioRegs = extern struct {
    RESERVED0: u32,
    PCFR1: u32,
    EXTICR: u32,
};

pub const IrqExti7_0: u8 = 20;
pub const IrqAdc: u8 = 29;
pub const IrqUsart1: u8 = 32;
pub const IrqTim1Up: u8 = 35;

pub const I2cRegs = extern struct {
    CTLR1: u16,
    RESERVED0: u16,
    CTLR2: u16,
    RESERVED1: u16,
    OADDR1: u16,
    RESERVED2: u16,
    OADDR2: u16,
    RESERVED3: u16,
    DATAR: u16,
    RESERVED4: u16,
    STAR1: u16,
    RESERVED5: u16,
    STAR2: u16,
    RESERVED6: u16,
    CKCFGR: u16,
    RESERVED7: u16,
};

pub const SpiRegs = extern struct {
    CTLR1: u16,
    RESERVED0: u16,
    CTLR2: u16,
    RESERVED1: u16,
    STATR: u16,
    RESERVED2: u16,
    DATAR: u16,
    RESERVED3: u16,
    CRCR: u16,
    RESERVED4: u16,
    RCRCR: u16,
    RESERVED5: u16,
    TCRCR: u16,
    RESERVED6: u16,
};

// SPI_CTLR1 bits
pub const SPI_CTLR1_CPHA: u16 = 1 << 0;
pub const SPI_CTLR1_CPOL: u16 = 1 << 1;
pub const SPI_CTLR1_MSTR: u16 = 1 << 2;
pub const SPI_CTLR1_BR_SHIFT: u4 = 3; // BR[2:0] baud rate divider
pub const SPI_CTLR1_SPE: u16 = 1 << 6;
pub const SPI_CTLR1_LSBFIRST: u16 = 1 << 7;
pub const SPI_CTLR1_SSI: u16 = 1 << 8;
pub const SPI_CTLR1_SSM: u16 = 1 << 9;
pub const SPI_CTLR1_RXONLY: u16 = 1 << 10;
pub const SPI_CTLR1_DFF: u16 = 1 << 11; // 0 = 8-bit, 1 = 16-bit
pub const SPI_CTLR1_BIDIOE: u16 = 1 << 14;
pub const SPI_CTLR1_BIDIMODE: u16 = 1 << 15;

// SPI_CTLR2 bits
pub const SPI_CTLR2_TXDMAEN: u16 = 1 << 1;
pub const SPI_CTLR2_RXDMAEN: u16 = 1 << 0;

// SPI_STATR bits
pub const SPI_STATR_RXNE: u16 = 1 << 0;
pub const SPI_STATR_TXE: u16 = 1 << 1;
pub const SPI_STATR_BSY: u16 = 1 << 7;

// DMA: CH32V003 has DMA1 with 7 channels. Each channel block is 20 bytes,
// starting at offset 0x08 (the first 8 bytes are the shared INTFR/INTFCR).
pub const DmaChannelRegs = extern struct {
    CFGR: u32, // configuration
    CNTR: u32, // transfer count
    PADDR: u32, // peripheral address
    MADDR: u32, // memory address
    RESERVED0: u32,
};

pub const DmaRegs = extern struct {
    INTFR: u32, // interrupt flag
    INTFCR: u32, // interrupt flag clear
    channels: [7]DmaChannelRegs,
};

// DMA_CFGR bits
pub const DMA_CFGR_EN: u32 = 1 << 0;
pub const DMA_CFGR_TCIE: u32 = 1 << 1; // transfer complete interrupt
pub const DMA_CFGR_DIR_MEM2PERIPH: u32 = 1 << 4; // 1 = read from memory
pub const DMA_CFGR_CIRC: u32 = 1 << 5; // circular mode
pub const DMA_CFGR_PINC: u32 = 1 << 6; // peripheral increment
pub const DMA_CFGR_MINC: u32 = 1 << 7; // memory increment
pub const DMA_CFGR_PSIZE_8: u32 = 0 << 8;
pub const DMA_CFGR_PSIZE_16: u32 = 1 << 8;
pub const DMA_CFGR_PSIZE_32: u32 = 2 << 8;
pub const DMA_CFGR_MSIZE_8: u32 = 0 << 10;
pub const DMA_CFGR_MSIZE_16: u32 = 1 << 10;
pub const DMA_CFGR_MSIZE_32: u32 = 2 << 10;
pub const DMA_CFGR_PL_HIGH: u32 = 2 << 12; // priority level

// DMA_INTFR / INTFCR: 4 bits per channel (GIF, TCIF, HTIF, TEIF).
pub fn dmaChannelTcifBit(channel: u3) u32 {
    return @as(u32, 1) << (@as(u5, channel - 1) * 4 + 1);
}
pub fn dmaChannelGifBit(channel: u3) u32 {
    return @as(u32, 1) << (@as(u5, channel - 1) * 4);
}

pub fn rcc() *volatile RccRegs {
    return @ptrFromInt(RCC_BASE);
}

pub fn flash() *volatile FlashRegs {
    return @ptrFromInt(FLASH_R_BASE);
}

pub fn gpioA() *volatile GpioRegs {
    return @ptrFromInt(GPIOA_BASE);
}

pub fn gpioC() *volatile GpioRegs {
    return @ptrFromInt(GPIOC_BASE);
}

pub fn gpioD() *volatile GpioRegs {
    return @ptrFromInt(GPIOD_BASE);
}

pub fn systick() *volatile SysTickRegs {
    return @ptrFromInt(SYSTICK_BASE);
}

pub fn i2c1() *volatile I2cRegs {
    return @ptrFromInt(I2C1_BASE);
}

pub fn usart1() *volatile UsartRegs {
    return @ptrFromInt(USART1_BASE);
}

pub fn tim1() *volatile TimRegs {
    return @ptrFromInt(TIM1_BASE);
}

pub fn tim2() *volatile TimRegs {
    return @ptrFromInt(TIM2_BASE);
}

pub fn adc1() *volatile AdcRegs {
    return @ptrFromInt(ADC1_BASE);
}

pub fn exti() *volatile ExtiRegs {
    return @ptrFromInt(EXTI_BASE);
}

pub fn afio() *volatile AfioRegs {
    return @ptrFromInt(AFIO_BASE);
}

pub fn spi1() *volatile SpiRegs {
    return @ptrFromInt(SPI1_BASE);
}

pub fn dma1() *volatile DmaRegs {
    return @ptrFromInt(DMA1_BASE);
}

pub fn pficEnableIrq(irqn: u8) void {
    const reg_index: usize = irqn / 32;
    const bit: u32 = @as(u32, 1) << @as(u5, @intCast(irqn % 32));
    const addr = PFIC_BASE + 0x100 + (reg_index * 4);
    const reg: *volatile u32 = @ptrFromInt(addr);
    reg.* = bit;
}
