// Suzu-based song demo
//
// Controls:
//   up/down     cutoff
//   left/right  resonance
//   a           drums on/off
//   b           bass on/off

const std = @import("std");
const cart = @import("cart-api");
const patch = @import("patch");

const pcm = @import("pcm.zig");
const scope = @import("scope.zig");

comptime {
    cart.export_start_code();
    std.debug.assert(patch.sample_rate == pcm.sample_rate);
}

var memory: [patch.memory_size]u8 align(8) = undefined;

var busy_us: u64 = 0;
var rendered_frames: u64 = 0;
var last_controls: cart.Controls = .none;
var drums_on = true;
var bass_on = true;

const white: cart.DisplayColor = .{ .r = 31, .g = 63, .b = 31 };
const black: cart.DisplayColor = .{ .r = 0, .g = 0, .b = 0 };

pub fn start() void {
    // The button that launched the cart is still down.
    last_controls = cart.controls.*;
    @memcpy(&memory, patch.memory_init);

    cart.set_double_buffer_mode(.copy_forward);
    cart.rect(.{ .x = 0, .y = 0, .width = cart.screen_width, .height = cart.screen_height, .fill_color = black });
    cart.text(.{ .str = "suzu", .x = 4, .y = 4, .scale = 2, .text_color = white });
    // I2S clock stays at 32 kHz after exit.
    cart.text(.{ .str = "Reset badge before", .x = 4, .y = 108, .text_color = white });
    cart.text(.{ .str = "playing other carts", .x = 4, .y = 118, .text_color = white });

    // Silent in the sim: the suzu object is arm32 only.
    if (!cart.is_simulator) pcm.init();
}

pub fn update() void {
    applyControls();

    if (!cart.is_simulator) {
        const t0 = cart.micros_since_boot();
        pcm.pump({}, render);
        busy_us += cart.micros_since_boot() - t0;
    }

    drawStatus();
    if (!cart.is_simulator) scope.draw();
}

fn render(_: void, out: []f32) void {
    const outs = [_][*]f32{out.ptr};
    patch.suzu_process(null, &outs, @intCast(out.len), &memory, &patch.shared);
    rendered_frames += out.len;
}

fn applyControls() void {
    const now = cart.controls.*;
    defer last_controls = now;

    if (now.up) nudge(patch.params.cutoff, 1.02);
    if (now.down) nudge(patch.params.cutoff, 1.0 / 1.02);
    if (now.left) nudge(patch.params.damp, 1.03);
    if (now.right) nudge(patch.params.damp, 1.0 / 1.03);

    if (now.a and !last_controls.a) {
        drums_on = !drums_on;
        set(patch.params.drum_level, if (drums_on) patch.params.drum_level.default else 0);
    }
    if (now.b and !last_controls.b) {
        bass_on = !bass_on;
        set(patch.params.bass_level, if (bass_on) patch.params.bass_level.default else 0);
    }
}

fn cell(param: patch.Param) *f32 {
    return @ptrCast(@alignCast(&memory[param.offset]));
}

/// Clamped: suzu's range proofs assume params stay in bounds.
fn set(param: patch.Param, value: f32) void {
    cell(param).* = std.math.clamp(value, param.min, param.max);
}

fn nudge(param: patch.Param, factor: f32) void {
    set(param, cell(param).* * factor);
}

fn drawStatus() void {
    var buf: [24]u8 = undefined;
    const audio_us = rendered_frames * 1_000_000 / pcm.sample_rate;
    const load = if (audio_us == 0) 0 else busy_us * 100 / audio_us;

    line(32, std.fmt.bufPrint(&buf, "cutoff {d:>5.0} Hz", .{cell(patch.params.cutoff).*}) catch unreachable); // fits in 24
    line(44, std.fmt.bufPrint(&buf, "damp   {d:>5.2}", .{cell(patch.params.damp).*}) catch unreachable);
    line(60, std.fmt.bufPrint(&buf, "cpu {d:>3}%  xrun {d}", .{ load, pcm.underruns }) catch unreachable);
}

fn line(y: i32, str: []const u8) void {
    cart.rect(.{ .x = 4, .y = y, .width = 152, .height = 8, .fill_color = black });
    cart.text(.{ .str = str, .x = 4, .y = y, .text_color = white });
}
