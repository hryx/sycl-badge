//! 16-bit PCM to the amp at 32 kHz, bypassing the SDK's u8 ring.
//! DMA channel 3 loops `ring` into the I2S TX FIFO, `pump` refills behind it.
//! I2S is PIO0 SM0: the OS takes the first free SM and nothing else uses PIO0.
//! Notes: suzu's notes/todo/badge_cart.md.

const std = @import("std");
const microzig = @import("microzig");

const DMA = microzig.chip.peripherals.DMA;
const PIO0 = microzig.chip.peripherals.PIO0;

pub const sample_rate = 32000;

const SIO = microzig.chip.peripherals.SIO;

const amp_enable_mask: u32 = 1 << 8;

const ring_log2_bytes = 14;
var ring: [(1 << ring_log2_bytes) / 4]u32 align(1 << ring_log2_bytes) = @splat(0);
const ring_mask: u32 = ring.len - 1;
const lead_frames = 256;
const chunk_frames = 512;

var cursor: u32 = 0;
var ahead_last: u32 = 0;
var hw_last: u32 = 0;
var scratch: [chunk_frames]f32 = undefined;

pub var underruns: u32 = 0;

pub fn init() void {
    SIO.GPIO_OUT_CLR.write(.{ .GPIO_OUT_CLR = amp_enable_mask });

    // 2 PIO cycles per bit, 32 bits per frame.
    // 150 MHz / (2 * 32 * 32000) = 73 + 62/256, exact.
    PIO0.SM0_CLKDIV.write(.{ .INT = 73, .FRAC = 62 });

    DMA.CH3_READ_ADDR.write(.{ .CH3_READ_ADDR = @intCast(@intFromPtr(&ring)) });
    DMA.CH3_WRITE_ADDR.write(.{ .CH3_WRITE_ADDR = @intCast(@intFromPtr(&PIO0.TXF0)) });
    // ENDLESS never decrements. Any nonzero count.
    DMA.CH3_TRANS_COUNT.write(.{ .COUNT = 1, .MODE = .ENDLESS });
    DMA.CH3_CTRL_TRIG.write(.{
        .EN = 1,
        .DATA_SIZE = .size_32,
        .INCR_READ = 1,
        .RING_SIZE = @fromBackingInt(@intCast(ring_log2_bytes)),
        .RING_SEL = 0,
        .CHAIN_TO = 3,
        .TREQ_SEL = .pio0_tx0,
        .IRQ_QUIET = 1,
    });

    hw_last = hardwareIndex();
    cursor = (hw_last + lead_frames) & ring_mask;
    ahead_last = lead_frames;

    // Amp on only once the clocks run.
    SIO.GPIO_OUT_SET.write(.{ .GPIO_OUT_SET = amp_enable_mask });
}

/// `render` fills f32 frames in [-1, 1], at most 512 per call.
pub fn pump(context: anytype, comptime render: fn (@TypeOf(context), []f32) void) void {
    const hw = hardwareIndex();
    // Underrun: DMA overtook the cursor.
    if (((hw -% hw_last) & ring_mask) > ahead_last) {
        underruns += 1;
        cursor = (hw + lead_frames) & ring_mask;
    }

    var free = ring.len - 1 - ((cursor -% hw) & ring_mask);
    while (free > 0) {
        const frames = @min(free, chunk_frames);
        render(context, scratch[0..frames]);
        for (scratch[0..frames]) |x| {
            ring[cursor] = pack(x);
            cursor = (cursor + 1) & ring_mask;
        }
        free -= frames;
    }

    hw_last = hw;
    ahead_last = (cursor -% hw) & ring_mask;
}

/// Ring index of the frame the DMA plays next.
pub fn playhead() u32 {
    return hardwareIndex();
}

/// Frames written but not played yet.
pub fn queued() u32 {
    return (cursor -% hardwareIndex()) & ring_mask;
}

/// Frame at ring index `index`, as written by `pump`.
pub fn frameAt(index: u32) f32 {
    const bits: u32 = ring[index & ring_mask] >> 16;
    return @as(f32, @floatFromInt(@as(i16, @bitCast(@as(u16, @intCast(bits)))))) / 32768.0;
}

fn hardwareIndex() u32 {
    const base: u32 = @intCast(@intFromPtr(&ring));
    return (DMA.CH3_READ_ADDR.raw -% base) / 4 & ring_mask;
}

fn pack(x: f32) u32 {
    const sample: i16 = @intFromFloat(std.math.clamp(x, -1.0, 1.0) * 32767.0);
    const bits: u32 = @as(u16, @bitCast(sample));
    return bits << 16 | bits;
}
