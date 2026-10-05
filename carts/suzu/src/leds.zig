//! Neopixels: kick, snare, hat and bass notes flash on their steps, the
//! last LED is a peak meter.

const std = @import("std");
const cart = @import("cart-api");

const pcm = @import("pcm.zig");
const song = @import("song.zig");

const frames_per_step: u64 = @intFromFloat(pcm.sample_rate / song.step_rate_hz);
const flash_peak = 160.0;
const flash_decay = 0.8;
const meter_peak = 127.0;
const meter_decay = 0.9;
const meter_window = 512;

const Rgb = struct { r: f32, g: f32, b: f32 };

const kick_color: Rgb = .{ .r = 1, .g = 0.35, .b = 0 };
const snare_color: Rgb = .{ .r = 0, .g = 0.8, .b = 1 };
const hat_color: Rgb = .{ .r = 0.7, .g = 0.7, .b = 0.7 };
const bass_color: Rgb = .{ .r = 0.8, .g = 0, .b = 1 };

var flash: [4]f32 = @splat(0);
var last_step: ?u64 = null;
var peak: f32 = 0;

/// `audible_frame` is the song frame coming out of the speaker now.
pub fn update(audible_frame: u64, drums_on: bool, bass_on: bool) void {
    for (&flash) |*level| level.* *= flash_decay;

    const step_count = audible_frame / frames_per_step;
    if (last_step != step_count) {
        last_step = step_count;
        const step: usize = @intCast(step_count % song.bass.hz.len);
        if (drums_on and song.kick[step] > 0) flash[0] = 1;
        if (drums_on and song.snare[step] > 0) flash[1] = 1;
        if (drums_on and song.hat[step] > 0) flash[2] = 1;
        if (bass_on and song.bass.attack[step] > 0) flash[3] = 1;
    }

    const head = pcm.playhead();
    var loudest: f32 = 0;
    for (0..meter_window) |i| loudest = @max(loudest, @abs(pcm.frameAt(head + @as(u32, @intCast(i)))));
    peak = @max(loudest, peak * meter_decay);

    cart.neopixels[0] = color(kick_color, flash[0] * flash_peak);
    cart.neopixels[1] = color(snare_color, flash[1] * flash_peak);
    cart.neopixels[2] = color(hat_color, flash[2] * flash_peak);
    cart.neopixels[3] = color(bass_color, flash[3] * flash_peak);
    cart.neopixels[4] = color(meterColor(peak), peak * meter_peak);
}

/// Green, then yellow fading to red over the top 20%.
fn meterColor(level: f32) Rgb {
    if (level < 0.8) return .{ .r = 0, .g = 1, .b = 0 };
    const t = @min((level - 0.8) / 0.2, 1);
    return .{ .r = 1, .g = 1 - t, .b = 0 };
}

fn color(rgb: Rgb, brightness: f32) cart.NeopixelColor {
    return .{
        .r = @intFromFloat(rgb.r * brightness),
        .g = @intFromFloat(rgb.g * brightness),
        .b = @intFromFloat(rgb.b * brightness),
    };
}
