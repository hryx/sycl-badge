const std = @import("std");

pub const bpm = 120.0;
pub const steps_per_beat = 4;
pub const steps_per_bar = 4 * steps_per_beat;
pub const step_rate_hz: f32 = bpm / 60.0 * steps_per_beat;

const kick_1 = "x..x ..x. x... ....";
const kick_2 = "x.xx ..x. xxx. .x..";
const kick_fill = "x..x ..x. x.x. x...";

const snare_1 = ".... x... .... x...";
const snare_2 = ".... x... .... x.xx";
const snare_fill = ".... x... ..xx xxxx";

const hat_1 = "..x. ..x. .x.x ...o";
const hat_2 = "..x. ..x. .x.x ....";
const hat_fill = "..x. ..x. .... ....";

pub const kick = hits(&.{
    kick_1,
    kick_1,
    kick_1,
    kick_2,
    kick_1,
    kick_1,
    kick_1,
    kick_fill,
});

pub const snare = hits(&.{
    snare_1,
    snare_1,
    snare_1,
    snare_2,
    snare_1,
    snare_1,
    snare_1,
    snare_fill,
});

pub const hat = hits(&.{
    hat_1,
    hat_2,
    hat_1,
    hat_2,
    hat_1,
    hat_2,
    hat_1,
    hat_fill,
});

/// `at` and `len` are steps from the start of the note's bar.
pub const Note = struct {
    at: u8,
    len: u8,
    key: []const u8,
    /// Semitones.
    vibrato: f32 = 0,
};

const bass_1 = [_]Note{
    .{ .at = 0, .len = 2, .key = "a2" },
    .{ .at = 3, .len = 1, .key = "a2" },
    .{ .at = 5, .len = 1, .key = "a2" },
    .{ .at = 6, .len = 1, .key = "c3" },
    .{ .at = 8, .len = 2, .key = "a2" },
    .{ .at = 11, .len = 1, .key = "g2" },
    .{ .at = 13, .len = 1, .key = "e2" },
    .{ .at = 14, .len = 1, .key = "g2" },
};

const bass_2 = [_]Note{
    .{ .at = 0, .len = 2, .key = "a2" },
    .{ .at = 3, .len = 1, .key = "a2" },
    .{ .at = 5, .len = 1, .key = "a2" },
    .{ .at = 6, .len = 1, .key = "c3" },
    .{ .at = 8, .len = 2, .key = "d3" },
    .{ .at = 10, .len = 1, .key = "c3" },
    .{ .at = 12, .len = 2, .key = "g2" },
    .{ .at = 14, .len = 1, .key = "e2" },
};

const bass_3 = [_]Note{
    .{ .at = 0, .len = 2, .key = "f2" },
    .{ .at = 3, .len = 1, .key = "f2" },
    .{ .at = 5, .len = 1, .key = "f2" },
    .{ .at = 6, .len = 1, .key = "a2" },
    .{ .at = 8, .len = 2, .key = "f2" },
    .{ .at = 11, .len = 1, .key = "e2" },
    .{ .at = 13, .len = 1, .key = "c2" },
    .{ .at = 14, .len = 1, .key = "e2" },
};

const bass_4 = [_]Note{
    .{ .at = 0, .len = 2, .key = "g2" },
    .{ .at = 3, .len = 1, .key = "g2" },
    .{ .at = 5, .len = 1, .key = "g2" },
    .{ .at = 6, .len = 1, .key = "b2" },
    .{ .at = 8, .len = 2, .key = "d3" },
    .{ .at = 10, .len = 1, .key = "c3" },
    .{ .at = 11, .len = 1, .key = "b2" },
    .{ .at = 12, .len = 3, .key = "g2" },
};

const bass_5 = [_]Note{
    .{ .at = 0, .len = 2, .key = "a2" },
    .{ .at = 3, .len = 1, .key = "a2" },
    .{ .at = 5, .len = 1, .key = "a2" },
    .{ .at = 6, .len = 1, .key = "c3" },
    .{ .at = 8, .len = 6, .key = "e3", .vibrato = 0.4 },
    .{ .at = 14, .len = 1, .key = "g2" },
};

const bass_6 = [_]Note{
    .{ .at = 0, .len = 2, .key = "g2" },
    .{ .at = 3, .len = 1, .key = "g2" },
    .{ .at = 5, .len = 1, .key = "g2" },
    .{ .at = 6, .len = 1, .key = "b2" },
} ++ trill(8, 6, "d3", "e3") ++ [_]Note{
    .{ .at = 14, .len = 2, .key = "a3", .vibrato = 0.3 },
};

pub const bass = sequence(&.{
    &bass_1,
    &bass_2,
    &bass_3,
    &bass_4,
    &bass_5,
    &bass_2,
    &bass_3,
    &bass_6,
});

// One-step notes alternating between `low` and `high`
pub fn trill(comptime at: u8, comptime len: u8, comptime low: []const u8, comptime high: []const u8) [len]Note {
    var out: [len]Note = undefined;
    for (&out, 0..) |*note, i| {
        note.* = .{ .at = at + @as(u8, @intCast(i)), .len = 1, .key = if (i % 2 == 0) low else high };
    }
    return out;
}

pub fn Tables(comptime len: usize) type {
    return struct {
        /// Held through releases so the tail keeps its pitch
        hz: [len]f32,
        open: [len]f32,
        /// Gate dips here to retrigger back-to-back notes
        attack: [len]f32,
        vibrato: [len]f32,
    };
}

pub fn sequence(comptime bars: []const []const Note) Tables(bars.len * steps_per_bar) {
    @setEvalBranchQuota(100_000);
    const len = bars.len * steps_per_bar;
    var out: Tables(len) = undefined;
    @memset(&out.open, 0);
    @memset(&out.attack, 0);

    // Steps before the first note carry the last note's tail around the loop.
    const last_bar = bars[bars.len - 1];
    if (last_bar.len == 0) @compileError("sequence: last bar is empty");
    var hz = noteHz(last_bar[last_bar.len - 1].key);
    var vibrato = last_bar[last_bar.len - 1].vibrato;

    var filled: usize = 0;
    var end: usize = 0;
    for (bars, 0..) |bar, bar_index| {
        for (bar) |note| {
            const start = bar_index * steps_per_bar + note.at;
            const where = std.fmt.comptimePrint("bar {d} step {d}", .{ bar_index, note.at });
            if (note.len == 0) @compileError("sequence: empty note at " ++ where);
            if (start < end) @compileError("sequence: overlap at " ++ where);
            end = start + note.len;
            if (end > len) @compileError("sequence: note runs past the end at " ++ where);

            while (filled < start) : (filled += 1) {
                out.hz[filled] = hz;
                out.vibrato[filled] = vibrato;
            }
            hz = noteHz(note.key);
            vibrato = note.vibrato;
            out.attack[start] = 1;
            @memset(out.open[start..end], 1);
        }
    }
    while (filled < len) : (filled += 1) {
        out.hz[filled] = hz;
        out.vibrato[filled] = vibrato;
    }
    return out;
}

/// One string per bar: `x` hits, `o` open hits (2), `.` rests, spaces
/// for reading. Tracks without an open sound play `o` like `x`.
pub fn hits(comptime bars: []const []const u8) [bars.len * steps_per_bar]f32 {
    @setEvalBranchQuota(100_000);
    var out: [bars.len * steps_per_bar]f32 = undefined;
    var i: usize = 0;
    for (bars, 0..) |bar, bar_index| {
        const start = i;
        for (bar) |c| switch (c) {
            'x', 'o', '.' => {
                if (i - start == steps_per_bar) @compileError(std.fmt.comptimePrint("hits: bar {d} is too long", .{bar_index}));
                out[i] = switch (c) {
                    'x' => 1,
                    'o' => 2,
                    else => 0,
                };
                i += 1;
            },
            ' ' => {},
            else => @compileError("hits: '" ++ .{c} ++ "' is not x, o or ."),
        };
        if (i - start != steps_per_bar) @compileError(std.fmt.comptimePrint("hits: bar {d} is too short", .{bar_index}));
    }
    return out;
}

/// Convert note names to Hz where A4 = 440 Hz
fn noteHz(comptime name: []const u8) f32 {
    const bad = "note: can't read '" ++ name ++ "'";
    if (name.len < 2) @compileError(bad);
    var semis: i32 = switch (name[0]) {
        'c' => 0,
        'd' => 2,
        'e' => 4,
        'f' => 5,
        'g' => 7,
        'a' => 9,
        'b' => 11,
        else => @compileError(bad),
    };
    var rest: []const u8 = name[1..];
    if (rest.len > 1) switch (rest[0]) {
        '#' => {
            semis += 1;
            rest = rest[1..];
        },
        'b' => {
            semis -= 1;
            rest = rest[1..];
        },
        else => {},
    };
    const octave = std.fmt.parseInt(i32, rest, 10) catch @compileError(bad);
    const midi = 12 * (octave + 1) + semis;
    return @floatCast(440.0 * @exp2(@as(f64, @floatFromInt(midi - 69)) / 12.0));
}

test "song sequence" {
    const bar = [_]Note{
        .{ .at = 0, .len = 2, .key = "a4", .vibrato = 0.5 },
        .{ .at = 3, .len = 1, .key = "c4" },
        .{ .at = 4, .len = 1, .key = "c4" },
    };
    const t = comptime sequence(&.{&bar});
    try std.testing.expectEqualSlices(f32, &.{ 1, 1, 0, 1, 1, 0 }, t.open[0..6]);
    try std.testing.expectEqualSlices(f32, &.{ 1, 0, 0, 1, 1, 0 }, t.attack[0..6]);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.5, 0.5, 0, 0 }, t.vibrato[0..5]);
    try std.testing.expectEqual(@as(f32, 440), t.hz[2]);
    try std.testing.expectApproxEqRel(@as(f32, 261.6256), t.hz[3], 1e-5);
    try std.testing.expectEqual(t.hz[3], t.hz[15]);
}

test "trill" {
    const notes = trill(8, 3, "d3", "e3");
    try std.testing.expectEqual(10, notes[2].at);
    try std.testing.expectEqualStrings("e3", notes[1].key);
}

test "song length" {
    try std.testing.expectEqual(8 * steps_per_bar, bass.hz.len);
    try std.testing.expectEqual(bass.hz.len, kick.len);
    try std.testing.expectEqual(bass.hz.len, snare.len);
    try std.testing.expectEqual(bass.hz.len, hat.len);
}
