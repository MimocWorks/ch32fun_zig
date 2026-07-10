//! CH32V003 内蔵 FLASH への書き込み HAL。
//!
//! CH32V003 の FLASH は「fast プログラム」モードで 64 バイト = 1 ページ単位の
//! 消去 / 書き込みを行う。 本モジュールは:
//!
//!   - unlock()                    main / fast の両ロックを解除
//!   - lock()                      ロックし直す
//!   - erasePage(addr)             addr を含むページを消去 (64B)
//!   - programPage(addr, &[64]u8)  消去済みページに 64B を書き込む
//!   - writePage(addr, &[64]u8)    erase + program のコンボ
//!   - readPage(addr, &[64]u8)     書かれている内容を読み出す
//!   - storage helpers (Slot)       1 ページに 1 値 を載せる KV 風の薄いラッパ
//!
//! 物理的な書き換え可能回数は 10,000 回程度 (TRM 値)。 頻繁に書く用途では
//! 寿命を意識して、 ページ内で位置をずらす wear-leveling を別途実装する必要がある。

const regs = @import("../periph/registers.zig");
const std = @import("std");

pub const page_size: usize = 64;
pub const Page = [page_size]u8;

pub const Error = error{
    UnlockFailed,
    BusyTimeout,
    WriteProtected,
    Misaligned,
    OutOfRange,
    Verify,
};

extern var _user_data_start: u8;

/// リンカで予約した USER_DATA 領域の先頭物理アドレス。
pub fn userDataAddr() usize {
    return @intFromPtr(&_user_data_start);
}

/// CH32V003 の FLASH レンジ。
pub const flash_origin: usize = 0x0800_0000;
pub const flash_end: usize = 0x0800_4000;

fn waitBusy() Error!void {
    const f = regs.flash();
    var timeout: u32 = 200_000;
    while ((f.STATR & regs.FLASH_STATR_BSY) != 0) {
        if (timeout == 0) return Error.BusyTimeout;
        timeout -= 1;
    }
    if ((f.STATR & regs.FLASH_STATR_WRPRTERR) != 0) {
        // sticky bit を落とす (1 を書いてクリア)
        f.STATR = regs.FLASH_STATR_WRPRTERR;
        return Error.WriteProtected;
    }
    // EOP は読み流す。 次の操作で参照しないのでクリアだけしておく。
    if ((f.STATR & regs.FLASH_STATR_EOP) != 0) f.STATR = regs.FLASH_STATR_EOP;
}

/// FLASH の主ロックと fast プログラムロックの両方を解除する。
pub fn unlock() Error!void {
    const f = regs.flash();
    if ((f.CTLR & regs.FLASH_CTLR_LOCK) != 0) {
        f.KEYR = regs.FLASH_KEY1;
        f.KEYR = regs.FLASH_KEY2;
    }
    if ((f.CTLR & regs.FLASH_CTLR_FAST_LOCK) != 0) {
        f.MODEKEYR = regs.FLASH_KEY1;
        f.MODEKEYR = regs.FLASH_KEY2;
    }
    if ((f.CTLR & (regs.FLASH_CTLR_LOCK | regs.FLASH_CTLR_FAST_LOCK)) != 0) {
        return Error.UnlockFailed;
    }
}

/// 再ロックする。 書き込み後に必ず呼ぶのが安全策。
pub fn lock() void {
    const f = regs.flash();
    f.CTLR = f.CTLR | regs.FLASH_CTLR_LOCK | regs.FLASH_CTLR_FAST_LOCK;
}

fn ensureInUserPage(addr: usize) Error!void {
    if (addr % page_size != 0) return Error.Misaligned;
    if (addr < flash_origin or addr >= flash_end) return Error.OutOfRange;
}

/// `addr` を含む 64B ページを消去する。 `addr` は 64B 境界である必要がある。
pub fn erasePage(addr: usize) Error!void {
    try ensureInUserPage(addr);
    const f = regs.flash();

    try waitBusy();
    f.CTLR = regs.FLASH_CTLR_PER;
    f.ADDR = @intCast(addr);
    f.CTLR = regs.FLASH_CTLR_PER | regs.FLASH_CTLR_STRT;
    try waitBusy();
    f.CTLR = 0;
}

/// 消去済みの 64B ページにバッファをそのまま書き込む。
/// 既に書かれている領域に上書きすると、 ビットは AND される (1→0 のみ可) ので、
/// 通常は事前に erasePage を呼ぶ。
pub fn programPage(addr: usize, src: *const Page) Error!void {
    try ensureInUserPage(addr);
    const f = regs.flash();

    try waitBusy();

    // バッファをリセットしてプログラムモードに入る
    f.CTLR = regs.FLASH_CTLR_PG;
    f.CTLR = regs.FLASH_CTLR_PG | regs.FLASH_CTLR_BUF_RST;
    try waitBusy();
    f.ADDR = @intCast(addr);

    // 64B = 16 ワードをページバッファに流し込む
    var i: usize = 0;
    while (i < page_size) : (i += 4) {
        const w = std.mem.readInt(u32, src[i..][0..4], .little);
        const dst: *volatile u32 = @ptrFromInt(addr + i);
        dst.* = w;
        f.CTLR = regs.FLASH_CTLR_PG | regs.FLASH_CTLR_BUF_LOAD;
        try waitBusy();
    }

    // ページ全体を実 FLASH に焼く
    f.CTLR = regs.FLASH_CTLR_PG | regs.FLASH_CTLR_STRT;
    try waitBusy();
    f.CTLR = 0;
}

/// erase + program を 1 関数で行う高レベル API。
pub fn writePage(addr: usize, src: *const Page) Error!void {
    try erasePage(addr);
    try programPage(addr, src);

    // ベリファイ
    const live: *const volatile Page = @ptrFromInt(addr);
    var k: usize = 0;
    while (k < page_size) : (k += 1) {
        if (live[k] != src[k]) return Error.Verify;
    }
}

/// FLASH 上の 64B ページをそのまま読む (FLASH は CPU の通常ロードで読める)。
pub fn readPage(addr: usize, dst: *Page) Error!void {
    try ensureInUserPage(addr);
    const src: *const Page = @ptrFromInt(addr);
    @memcpy(dst, src);
}

// ----------------------------------------------------------------------
// Slot — 1 ページに 1 つの値型を載せる薄い KV ストア
//
// レイアウト:
//   offset 0..1  : magic        (0xCAFE — 「有効データあり」のマーカ)
//   offset 2..3  : version      (任意の u16。 型レイアウト変更時にインクリメント想定)
//   offset 4..7  : reserved
//   offset 8..   : T のバイト列
//
// 1 ページに 1 値しか載せないので、 書き込みのたびにページを消去 + 再プログラム
// することになる。 寿命 (≒10k) を意識した使い方をすること。
// ----------------------------------------------------------------------

const SLOT_MAGIC: u16 = 0xCAFE;
const SLOT_HEADER_SIZE: usize = 8;

pub fn Slot(comptime T: type) type {
    if (@sizeOf(T) + SLOT_HEADER_SIZE > page_size) {
        @compileError("Slot 用の型は 56 バイト以下である必要があります");
    }
    return struct {
        const Self = @This();
        addr: usize,
        version: u16,

        pub fn init(addr: usize, version: u16) Self {
            return .{ .addr = addr, .version = version };
        }

        /// USER_DATA ページに紐づいた既定のスロットを返す。
        pub fn default(version: u16) Self {
            return .{ .addr = userDataAddr(), .version = version };
        }

        /// 保存されている値を読み出す。 magic / version が一致しなければ null。
        pub fn load(self: Self) ?T {
            const src: [*]const volatile u8 = @ptrFromInt(self.addr);
            const magic: u16 = @as(u16, src[0]) | (@as(u16, src[1]) << 8);
            const ver: u16 = @as(u16, src[2]) | (@as(u16, src[3]) << 8);
            if (magic != SLOT_MAGIC) return null;
            if (ver != self.version) return null;
            var out: T = undefined;
            const bytes = std.mem.asBytes(&out);
            var i: usize = 0;
            while (i < bytes.len) : (i += 1) bytes[i] = src[SLOT_HEADER_SIZE + i];
            return out;
        }

        /// 値を保存する (erase + program)。
        pub fn save(self: Self, value: T) Error!void {
            var page: Page = [_]u8{0xFF} ** page_size;
            std.mem.writeInt(u16, page[0..2], SLOT_MAGIC, .little);
            std.mem.writeInt(u16, page[2..4], self.version, .little);
            // 4..8 は 0xFF のまま (将来用)
            const bytes = std.mem.asBytes(&value);
            @memcpy(page[SLOT_HEADER_SIZE..][0..bytes.len], bytes);

            try unlock();
            defer lock();
            try writePage(self.addr, &page);
        }

        /// 値が無ければ default を返し、そのまま保存もする。
        pub fn loadOrInit(self: Self, default_value: T) Error!T {
            if (self.load()) |v| return v;
            try self.save(default_value);
            return default_value;
        }
    };
}
