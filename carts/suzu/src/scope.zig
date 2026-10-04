//! Draws the audio about to play, read straight from the pcm ring.

const std = @import("std");
const cart = @import("cart-api");

const pcm = @import("pcm.zig");

const x0 = 4;
const top = 72;
const width = 152;
const height = 32;
const frames_per_px = 4;
const trigger_search = 384;

const green: cart.DisplayColor = .{ .r = 8, .g = 63, .b = 16 };
const black: cart.DisplayColor = .{ .r = 0, .g = 0, .b = 0 };

pub fn draw() void {
    // Start on a rising zero crossing so the trace holds still.
    var start = pcm.playhead() + 1;
    for (0..trigger_search) |_| {
        if (pcm.frameAt(start - 1) < 0 and pcm.frameAt(start) >= 0) break;
        start += 1;
    }

    cart.rect(.{ .x = x0, .y = top, .width = width, .height = height, .fill_color = black });
    var y_prev = pixelY(pcm.frameAt(start));
    for (0..width) |x| {
        const y = pixelY(pcm.frameAt(start + @as(u32, @intCast(x * frames_per_px))));
        const y_min = @min(y, y_prev);
        cart.rect(.{
            .x = x0 + @as(i32, @intCast(x)),
            .y = y_min,
            .width = 1,
            .height = @intCast(@max(y, y_prev) - y_min + 1),
            .fill_color = green,
        });
        y_prev = y;
    }
}

fn pixelY(x: f32) i32 {
    const half = (height - 1) / 2;
    return top + half - @as(i32, @intFromFloat(std.math.clamp(x, -1.0, 1.0) * half));
}
