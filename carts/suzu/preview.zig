//! Host tool: JIT patch.zig and render 16 s to zig-out/suzu-preview.wav.
//!
//!     zig build suzu-preview

const std = @import("std");
const suzu = @import("suzu");

const patch = @import("patch.zig");

const compile = suzu.compile;
const Program = suzu.Program;

const seconds = 16;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.log.err("usage: suzu-preview <out.wav>", .{});
        std.process.exit(1);
    }

    var p = Program.init(gpa, patch.sample_rate);
    defer p.deinit();
    patch.build(&p) catch |err| {
        std.log.err("patch: {t}: {any}", .{ err, p.builder.diag });
        std.process.exit(1);
    };

    var jit = try compile.compileJitNative(gpa, &p, .{});
    defer jit.deinit();

    const frame_count = patch.sample_rate * seconds;
    const out = try gpa.alloc(f32, frame_count);
    defer gpa.free(out);
    const outs = [_]compile.OutBuffer{.{ .floats = out.ptr }};
    jit.process(null, &outs, frame_count);

    var peak: f32 = 0;
    var sum_squares: f64 = 0;
    var nans: usize = 0;
    for (out) |x| {
        if (std.math.isNan(x)) nans += 1 else {
            peak = @max(peak, @abs(x));
            sum_squares += x * x;
        }
    }
    const rms = @sqrt(sum_squares / frame_count);
    if (nans > 0 or rms < 0.01) {
        std.log.err("broken render: peak {d:.3}  rms {d:.3}  nan {d}", .{ peak, rms, nans });
        std.process.exit(1);
    }

    var wav: std.Io.Writer.Allocating = .init(gpa);
    defer wav.deinit();
    const w = &wav.writer;
    try w.writeAll("RIFF");
    try w.writeInt(u32, 36 + frame_count * 2, .little);
    try w.writeAll("WAVEfmt ");
    try w.writeInt(u32, 16, .little);
    try w.writeInt(u16, 1, .little);
    try w.writeInt(u16, 1, .little);
    try w.writeInt(u32, patch.sample_rate, .little);
    try w.writeInt(u32, patch.sample_rate * 2, .little);
    try w.writeInt(u16, 2, .little);
    try w.writeInt(u16, 16, .little);
    try w.writeAll("data");
    try w.writeInt(u32, frame_count * 2, .little);
    for (out) |x| {
        const sample: i16 = @intFromFloat(std.math.clamp(x, -1.0, 1.0) * 32767.0);
        try w.writeInt(i16, sample, .little);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[1], .data = wav.written() });
}
