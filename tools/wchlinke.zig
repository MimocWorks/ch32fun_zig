//! CH32V003 flash writer for a WCH-LinkE in RISC-V mode.
//! USB transport uses libusb at runtime; no minichlink headers or binary are used.
const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{ UsbLibraryMissing, UsbSymbolMissing, UsbFailure, DeviceNotFound, BadReply, WrongProgrammer, WrongChip, TargetUnavailable, FlashLocked, FlashTimeout, VerifyFailed, ImageTooLarge, EmptyImage, BadArguments, DebugFailure };

const Descriptor = extern struct {
    length: u8,
    descriptor_type: u8,
    usb_version: u16,
    device_class: u8,
    device_subclass: u8,
    device_protocol: u8,
    max_packet_size0: u8,
    vendor_id: u16,
    product_id: u16,
    device_version: u16,
    manufacturer: u8,
    product: u8,
    serial_number: u8,
    configurations: u8,
};

const Usb = struct {
    lib: std.DynLib,
    ctx: ?*anyopaque = null,
    handle: ?*anyopaque = null,
    init: *const fn (*?*anyopaque) callconv(.c) c_int,
    exit: *const fn (?*anyopaque) callconv(.c) void,
    get_device_list: *const fn (?*anyopaque, *?[*]?*anyopaque) callconv(.c) isize,
    free_device_list: *const fn ([*]?*anyopaque, c_int) callconv(.c) void,
    get_device_descriptor: *const fn (*anyopaque, *Descriptor) callconv(.c) c_int,
    open_device: *const fn (*anyopaque, *?*anyopaque) callconv(.c) c_int,
    close_device: *const fn (?*anyopaque) callconv(.c) void,
    claim_interface: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    release_interface: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    bulk_transfer: *const fn (?*anyopaque, u8, [*]u8, c_int, *c_int, c_uint) callconv(.c) c_int,

    fn symbol(lib: *std.DynLib, comptime T: type, name: [:0]const u8) Error!T {
        return lib.lookup(T, name) orelse Error.UsbSymbolMissing;
    }

    fn connect() !Usb {
        const names: []const []const u8 = switch (@import("builtin").os.tag) {
            .macos => &.{ "/opt/homebrew/lib/libusb-1.0.dylib", "/usr/local/lib/libusb-1.0.dylib", "libusb-1.0.dylib" },
            .linux => &.{ "libusb-1.0.so.0", "libusb-1.0.so" },
            else => @compileError("WCH-LinkE USB transport supports macOS and Linux"),
        };
        var lib: ?std.DynLib = null;
        for (names) |name| {
            lib = std.DynLib.open(name) catch null;
            if (lib != null) break;
        }
        var u = Usb{
            .lib = lib orelse return Error.UsbLibraryMissing,
            .init = undefined,
            .exit = undefined,
            .get_device_list = undefined,
            .free_device_list = undefined,
            .get_device_descriptor = undefined,
            .open_device = undefined,
            .close_device = undefined,
            .claim_interface = undefined,
            .release_interface = undefined,
            .bulk_transfer = undefined,
        };
        errdefer u.lib.close();
        u.init = try symbol(&u.lib, @TypeOf(u.init), "libusb_init");
        u.exit = try symbol(&u.lib, @TypeOf(u.exit), "libusb_exit");
        u.get_device_list = try symbol(&u.lib, @TypeOf(u.get_device_list), "libusb_get_device_list");
        u.free_device_list = try symbol(&u.lib, @TypeOf(u.free_device_list), "libusb_free_device_list");
        u.get_device_descriptor = try symbol(&u.lib, @TypeOf(u.get_device_descriptor), "libusb_get_device_descriptor");
        u.open_device = try symbol(&u.lib, @TypeOf(u.open_device), "libusb_open");
        u.close_device = try symbol(&u.lib, @TypeOf(u.close_device), "libusb_close");
        u.claim_interface = try symbol(&u.lib, @TypeOf(u.claim_interface), "libusb_claim_interface");
        u.release_interface = try symbol(&u.lib, @TypeOf(u.release_interface), "libusb_release_interface");
        u.bulk_transfer = try symbol(&u.lib, @TypeOf(u.bulk_transfer), "libusb_bulk_transfer");
        if (u.init(&u.ctx) != 0) return Error.UsbFailure;
        errdefer u.exit(u.ctx);
        var list: ?[*]?*anyopaque = null;
        const count = u.get_device_list(u.ctx, &list);
        if (count < 0 or list == null) return Error.UsbFailure;
        defer u.free_device_list(list.?, 1);
        for (list.?[0..@intCast(count)]) |device_opt| {
            const device = device_opt orelse continue;
            var desc: Descriptor = undefined;
            if (u.get_device_descriptor(device, &desc) != 0) continue;
            if (desc.vendor_id != 0x1a86 or desc.product_id != 0x8010) continue;
            if (u.open_device(device, &u.handle) != 0) return Error.UsbFailure;
            break;
        }
        if (u.handle == null) return Error.DeviceNotFound;
        errdefer u.close_device(u.handle);
        if (u.claim_interface(u.handle, 0) != 0) return Error.UsbFailure;
        return u;
    }

    fn deinit(u: *Usb) void {
        if (u.handle != null) {
            _ = u.release_interface(u.handle, 0);
            u.close_device(u.handle);
        }
        u.exit(u.ctx);
        u.lib.close();
    }

    fn command(u: *Usb, req: []const u8, reply: *[128]u8) Error![]const u8 {
        var sent: c_int = 0;
        if (u.bulk_transfer(u.handle, 0x01, @constCast(req.ptr), @intCast(req.len), &sent, 5000) != 0 or sent != req.len) return Error.UsbFailure;
        var received: c_int = 0;
        if (u.bulk_transfer(u.handle, 0x81, reply, reply.len, &received, 5000) != 0) return Error.UsbFailure;
        if (received < 3 or reply[0] != 0x82) return Error.BadReply;
        return reply[0..@intCast(received)];
    }
};

const Probe = struct {
    usb: *Usb,

    fn reg(p: *Probe, address: u8, value: ?u32) Error!u32 {
        const v = value orelse 0;
        const req = [_]u8{ 0x81, 0x08, 0x06, address, @truncate(v >> 24), @truncate(v >> 16), @truncate(v >> 8), @truncate(v), if (value == null) 1 else 2 };
        var reply: [128]u8 = undefined;
        const resp = try p.usb.command(&req, &reply);
        if (resp.len != 9 or resp[8] == 2 or resp[8] == 3) return Error.DebugFailure;
        return @as(u32, resp[4]) << 24 | @as(u32, resp[5]) << 16 | @as(u32, resp[6]) << 8 | resp[7];
    }
    fn wr(p: *Probe, address: u8, value: u32) Error!void {
        _ = try p.reg(address, value);
    }
    fn rd(p: *Probe, address: u8) Error!u32 {
        return p.reg(address, null);
    }

    fn waitOp(p: *Probe) Error!void {
        for (0..100) |_| {
            const status = try p.rd(0x16);
            if (status & 0x1000 != 0) continue;
            if (status & 0x700 != 0) {
                try p.wr(0x16, 0x700);
                return Error.DebugFailure;
            }
            return;
        }
        return Error.DebugFailure;
    }

    fn setup(p: *Probe) Error!void {
        var reply: [128]u8 = undefined;
        _ = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0xff }, &reply);
        const ver = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0x01 }, &reply);
        if (ver.len < 6 or ver[5] != 18) return Error.WrongProgrammer;
        _ = try p.usb.command(&.{ 0x81, 0x0c, 0x02, 0x01, 0x02 }, &reply);
        var connected = false;
        for (0..6) |_| {
            const target = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0x02 }, &reply);
            if (target.len >= 8 and target[0] == 0x82 and target[1] == 0x0d and target[3] == 0x09 and target[4] == 0x00 and target[5] == 0x30) {
                connected = true;
                break;
            }
            _ = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0x13 }, &reply);
            _ = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0xff }, &reply);
            _ = try p.usb.command(&.{ 0x81, 0x0b, 0x01, 0x01 }, &reply);
        }
        if (!connected) return Error.TargetUnavailable;
        try p.wr(0x10, 0x80000003);
        try p.wr(0x10, 0x80000001);
        try p.wr(0x10, 0x80000001);
        _ = try p.usb.command(&.{ 0x81, 0x0c, 0x02, 0x09, 0x01 }, &reply);
        // Enable the CH32 debug module and halt the core for program-buffer access.
        try p.wr(0x7e, 0x5aa50400);
        try p.wr(0x7d, 0x5aa50400);
        try p.wr(0x10, 0x80000001);
        const status = try p.rd(0x11);
        if (status == 0 or status == 0xffffffff) return Error.TargetUnavailable;
        try p.wr(0x16, 0x700);
        try p.wr(0x18, 0);
        const hart = try p.rd(0x12);
        const data_addr = 0xe0000000 | (hart & 0x7ff);
        try p.setRegister(10, data_addr);
        try p.setRegister(11, data_addr + 4);
        try p.setRegister(12, 0x4002200c);
        try p.setRegister(13, 0x00050000);
    }

    fn setRegister(p: *Probe, number: u8, value: u32) Error!void {
        try p.wr(0x04, value);
        try p.wr(0x17, 0x00231000 | @as(u32, number));
        try p.waitOp();
    }

    fn memoryRead(p: *Probe, address: u32) Error!u32 {
        try p.wr(0x18, 0);
        try p.wr(0x20, 0x0004a403); // lw x8,0(x9)
        try p.wr(0x21, 0x00100073); // ebreak
        try p.setRegister(9, address);
        try p.wr(0x17, 0x00241000); // execute program buffer
        try p.waitOp();
        try p.wr(0x17, 0x00221008); // x8 -> DATA0
        try p.waitOp();
        return p.rd(0x04);
    }

    fn memoryWrite(p: *Probe, address: u32, value: u32, flash_data: bool) Error!void {
        try p.wr(0x18, 0);
        try p.wr(0x20, 0x41844100); // DATA0/DATA1 -> x8/x9
        try p.wr(0x21, 0x0491c080); // sw x8,0(x9); addi x9,4
        try p.wr(0x22, 0x0001c184); // save address
        if (flash_data) {
            try p.wr(0x23, 0x4200c254); // acknowledge buffer load; read STATR
            try p.wr(0x24, 0xfc758805); // wait until not busy
            try p.wr(0x25, 0x90029002);
        } else {
            try p.wr(0x23, 0x90029002);
        }
        try p.wr(0x05, address);
        try p.wr(0x04, value);
        try p.wr(0x17, 0x00240000);
        try p.waitOp();
    }

    fn waitFlash(p: *Probe) Error!void {
        for (0..1000) |_| {
            const status = try p.memoryRead(0x4002200c);
            if (status & 0x10 != 0) return Error.FlashLocked;
            if (status & 3 == 0) return;
        }
        return Error.FlashTimeout;
    }

    fn unlock(p: *Probe) Error!void {
        const ctl = try p.memoryRead(0x40022010);
        if (ctl & 0x8080 == 0) return;
        for ([_]u32{ 0x40022004, 0x40022024 }) |key_addr| {
            try p.memoryWrite(key_addr, 0x45670123, false);
            try p.memoryWrite(key_addr, 0xcdef89ab, false);
        }
        if ((try p.memoryRead(0x40022010)) & 0x8080 != 0) return Error.FlashLocked;
    }

    fn flash(p: *Probe, image: []const u8) Error!void {
        try p.unlock();
        const pages = (image.len + 63) / 64;
        for (0..pages) |page| {
            const addr: u32 = 0x08000000 + @as(u32, @intCast(page * 64));
            var data: [64]u8 = @splat(0xff);
            const start = page * 64;
            const n = @min(64, image.len - start);
            @memcpy(data[0..n], image[start..][0..n]);
            try p.waitFlash();
            try p.memoryWrite(0x40022010, 0x00020000, false);
            try p.memoryWrite(0x40022014, addr, false);
            try p.memoryWrite(0x40022010, 0x00020040, false);
            try p.waitFlash();
            try p.memoryWrite(0x40022010, 0x00010000, false);
            try p.memoryWrite(0x40022010, 0x00090000, false);
            for (0..16) |word| {
                const i = word * 4;
                const v = std.mem.readInt(u32, data[i..][0..4], .little);
                try p.memoryWrite(addr + @as(u32, @intCast(i)), v, true);
            }
            try p.memoryWrite(0x40022014, addr, false);
            try p.memoryWrite(0x40022010, 0x00010040, false);
            try p.waitFlash();
            for (0..16) |word| {
                const i = word * 4;
                const expected = std.mem.readInt(u32, data[i..][0..4], .little);
                if (try p.memoryRead(addr + @as(u32, @intCast(i))) != expected) return Error.VerifyFailed;
            }
            if ((page + 1) % 16 == 0 or page + 1 == pages) std.debug.print("\r{d}/{d} pages verified", .{ page + 1, pages });
        }
        std.debug.print("\n", .{});
        var reply: [128]u8 = undefined;
        _ = try p.usb.command(&.{ 0x81, 0x0b, 0x01, 0x01 }, &reply);
        _ = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0x02 }, &reply);
        _ = try p.usb.command(&.{ 0x81, 0x0d, 0x01, 0xff }, &reply);
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    const args = init.args.vector;
    if (args.len != 2) {
        std.debug.print("usage: wchlinke <firmware.bin>\n", .{});
        return Error.BadArguments;
    }
    const path = std.mem.span(args[1]);
    const allocator: Allocator = std.heap.page_allocator;
    const image = try std.Io.Dir.cwd().readFileAlloc(std.Options.debug_io, path, allocator, .limited(16 * 1024 + 1));
    defer allocator.free(image);
    if (image.len == 0) return Error.EmptyImage;
    if (image.len > 16 * 1024 - 64) return Error.ImageTooLarge;
    var usb = try Usb.connect();
    defer usb.deinit();
    var probe = Probe{ .usb = &usb };
    try probe.setup();
    std.debug.print("WCH-LinkE / CH32V003: writing {d} bytes\n", .{image.len});
    try probe.flash(image);
}
