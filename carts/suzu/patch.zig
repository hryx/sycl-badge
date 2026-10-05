//! PWM pulse bass, resonant lowpass, kick, snare and an FM hat,
//! sequenced from song.zig. Baked on the host by bake.zig.

const std = @import("std");
const suzu = @import("suzu");
const dsp = @import("std_dsp");

const song = @import("src/song.zig");

const Program = suzu.Program;
const Value = Program.Value;

pub const sample_rate = 32000;

pub fn build(p: *Program) !void {
    const b = &p.builder;
    const rate = song.step_rate_hz;

    const cutoff = try p.addParam("cutoff", .float, 300, 4000, 900);
    const damp = try p.addParam("damp", .float, 0.1, 1.0, 0.2);
    const pwm = try p.addParam("pwm", .float, 0, 0.4, 0.3);
    const bass_level = try p.addParam("bass_level", .float, 0, 1, 0.6);
    const drum_level = try p.addParam("drum_level", .float, 0, 1, 0.7);

    const note_hz = try dsp.sequence.steps(b, &song.bass.hz, rate);
    const vibrato = try dsp.sequence.steps(b, &song.bass.vibrato, rate);
    const vibrato_lfo = (try p.call(dsp.oscillator.sine, &.{.{ .float = 5.5 }}))[0];
    // 2^(x/12) ~ 1 + 0.0578x, close enough under a semitone.
    const bend = try p.fma(try p.mul(vibrato, .{ .float = 0.0578 }), vibrato_lfo, .{ .float = 1 });
    const hz = try p.mul(note_hz, bend);
    const open = try dsp.sequence.steps(b, &song.bass.open, rate);
    const attack = try dsp.sequence.steps(b, &song.bass.attack, rate);
    const dip = try dsp.sequence.gate(b, rate, 0.05);
    const gate = try p.mul(open, try p.sub(.{ .float = 1 }, try p.mul(attack, dip)));

    const lfo = (try p.call(dsp.oscillator.sine, &.{.{ .float = 0.3 }}))[0];
    const lfo_unipolar = try p.fma(lfo, .{ .float = 0.5 }, .{ .float = 0.5 });
    const width = try p.sub(.{ .float = 0.5 }, try p.mul(pwm, lfo_unipolar));
    const pulse = try p.toFloat((try p.call(dsp.oscillator.rectangle, &.{ hz, width }))[0]);

    const env = (try p.call(dsp.dynamics.adsr, &.{
        gate,
        .{ .float = 0.003 },
        .{ .float = 0.25 },
        .{ .float = 0.4 },
        .{ .float = 0.08 },
    }))[0];
    const fc = try p.mul(cutoff, try p.fma(env, .{ .float = 1.5 }, .{ .float = 0.5 }));
    const lowpass = (try p.call(dsp.filter.svf, &.{ fc, damp, pulse }))[0];
    // The resonant peak shouts once it reaches the buzzer's loud band, so
    // trade level for resonance above ~500 Hz and leave low cutoffs alone.
    const knee = try p.min(try p.max(try p.fma(fc, .{ .float = 1.0 / 1000.0 }, .{ .float = -0.5 }), .{ .float = 0 }), .{ .float = 1 });
    const excess = try p.sub(try p.div(.{ .float = 1 }, damp), .{ .float = 1 });
    const tame = try p.div(.{ .float = 1 }, try p.fma(try p.mul(excess, knee), .{ .float = 0.25 }, .{ .float = 1 }));
    const bass = try p.mul(try p.mul(try p.mul(lowpass, tame), env), bass_level);

    const kick = try drum(p, wavTable(b.allocator, @embedFile("data/kick.wav")), &song.kick);
    const snare = try drum(p, wavTable(b.allocator, @embedFile("data/snare.wav")), &song.snare);
    const drums = try p.mul(try p.add(try p.add(kick, snare), try hat(p)), drum_level);

    const mix = (try p.call(dsp.drive.softclip, &.{try p.add(bass, drums)}))[0];
    try p.addOutput(mix);
}

fn drum(p: *Program, table: []const f32, comptime pattern: []const f32) !Value {
    const b = &p.builder;
    defer b.allocator.free(table);

    const rate = song.step_rate_hz;
    const steps = try dsp.sequence.steps(b, pattern, rate);
    const gate = try dsp.sequence.gate(b, rate, 0.5);
    const trig = try dsp.events.edge(b, try p.mul(steps, gate));
    return oneShot8(p, table, trig);
}

/// `sampler.oneShot` over 8-bit samples packed four to a cell, a quarter
/// of the f32 table's RAM. Sample k sits in byte lane k & 3 of cell k >> 2.
fn oneShot8(p: *Program, table: []const f32, trig: Value) !Value {
    const b = &p.builder;
    const n: i32 = @intCast(table.len);

    const cells = try b.allocator.alloc(i32, (table.len + 3) / 4);
    defer b.allocator.free(cells);
    @memset(cells, 0);
    for (table, 0..) |x, k| {
        const byte: i8 = @intFromFloat(@round(std.math.clamp(x, -1.0, 1.0) * 127.0));
        const lane: u5 = @intCast(8 * (k % 4));
        cells[k / 4] |= @bitCast(@as(u32, @as(u8, @bitCast(byte))) << lane);
    }
    const packed_mem = try b.addMemReadOnly(.int, cells);

    const pos = try b.addMem(.int, 1, .{ .read_write = .{ .int = .{ .min = 0, .max = n } } });
    const prev = try p.load(pos, .{ .int = 0 });
    const dec = try p.max(try p.sub(prev, .{ .int = 1 }), .{ .int = 0 });
    const next = try p.select(trig, &.{ dec, .{ .int = n } });
    try p.store(pos, .{ .int = 0 }, next);

    const k = try p.sub(.{ .int = n }, try p.max(next, .{ .int = 1 }));
    const cell = try p.load(packed_mem, try p.shr(k, .{ .int = 2 }));
    const lane_bits = try p.shl(try p.bitAnd(k, .{ .int = 3 }), .{ .int = 3 });
    const top = try p.shl(cell, try p.sub(.{ .int = 24 }, lane_bits));
    const sample = try p.mul(try p.toFloat(try p.shr(top, .{ .int = 24 })), .{ .float = 1.0 / 127.0 });

    const playing = try p.gt(next, .{ .int = 0 });
    return p.select(playing, &.{ .{ .float = 0.0 }, sample });
}

/// Two-operator FM with an inharmonic ratio for the metal. The index
/// always rides the short envelope for the bright attack. Open hits swap
/// the amp to a long envelope and keep a little index on it, so the tail
/// rings with some shimmer instead of hash. A closed hit chokes an open one.
fn hat(p: *Program) !Value {
    const b = &p.builder;
    const carrier_hz = 1700;
    const ratio = 1.47;
    const index = 3.0;
    const open_index = 1.2;
    const open_decay_s = 0.3;
    const level = 0.22;

    const rate = song.step_rate_hz;
    const steps = try dsp.sequence.steps(b, &song.hat, rate);
    const hit = try p.toFloat(try p.gt(steps, .{ .float = 0.5 }));
    const gate = try p.mul(hit, try dsp.sequence.gate(b, rate, 0.25));
    const trig = try dsp.events.edge(b, gate);
    const open = try dsp.events.latch(b, trig, try p.toFloat(try p.gt(steps, .{ .float = 1.5 })));

    const short = (try p.call(dsp.dynamics.adsr, &.{
        gate,
        .{ .float = 0.0005 },
        .{ .float = 0.035 },
        .{ .float = 0 },
        .{ .float = 0.02 },
    }))[0];
    const long = (try p.call(dsp.dynamics.adsr, &.{
        gate,
        .{ .float = 0.0005 },
        .{ .float = open_decay_s },
        .{ .float = 0 },
        .{ .float = open_decay_s },
    }))[0];
    const env = try p.fma(open, try p.sub(long, short), short);

    const tau = 2 * std.math.pi;
    const mod_phase = (try p.call(dsp.oscillator.ramp, &.{.{ .float = carrier_hz * ratio }}))[0];
    const carrier_phase = (try p.call(dsp.oscillator.ramp, &.{.{ .float = carrier_hz }}))[0];
    const modulator = try p.sin(try p.mul(mod_phase, .{ .float = tau }));
    const depth = try p.fma(open, try p.mul(long, .{ .float = open_index }), try p.mul(short, .{ .float = index }));
    const tone = try p.sin(try p.fma(modulator, depth, try p.mul(carrier_phase, .{ .float = tau })));
    return p.mul(try p.mul(tone, env), .{ .float = level });
}

/// 16-bit mono at `sample_rate` only. data/ is converted offline, no
/// resampling here.
fn wavTable(gpa: std.mem.Allocator, bytes: []const u8) []f32 {
    var pos: usize = 12;
    var format_ok = false;
    while (pos + 8 <= bytes.len) {
        const id = bytes[pos..][0..4];
        const len = std.mem.readInt(u32, bytes[pos + 4 ..][0..4], .little);
        const body = bytes[pos + 8 ..][0..len];
        if (std.mem.eql(u8, id, "fmt ")) {
            const channels = std.mem.readInt(u16, body[2..4], .little);
            const rate = std.mem.readInt(u32, body[4..8], .little);
            const bits = std.mem.readInt(u16, body[14..16], .little);
            format_ok = channels == 1 and rate == sample_rate and bits == 16;
        } else if (std.mem.eql(u8, id, "data")) {
            if (!format_ok) @panic("drum WAV must be 16-bit mono at 32 kHz");
            const table = gpa.alloc(f32, len / 2) catch @panic("out of memory");
            for (table, 0..) |*sample, i| {
                const raw = std.mem.readInt(i16, body[i * 2 ..][0..2], .little);
                sample.* = @as(f32, @floatFromInt(raw)) / 32768.0;
            }
            return table;
        }
        pos += 8 + len + (len & 1);
    }
    @panic("drum WAV has no data chunk");
}
