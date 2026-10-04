const std = @import("std");
const Build = std.Build;

/// suzu is a lazy path dependency so the repo builds without a suzu
/// checkout next to it.
pub fn build_cart(b: *Build, cart: *Build.Module, cart_api: *Build.Module, step: *Build.Step) void {
    _ = cart_api;
    const suzu_dep = b.lazyDependency("suzu", .{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) orelse return;

    const imports: []const Build.Module.Import = &.{
        .{ .name = "suzu", .module = suzu_dep.module("suzu") },
        .{ .name = "std_dsp", .module = suzu_dep.module("std_dsp") },
    };

    const bake = b.addExecutable(.{
        .name = "suzu-bake",
        .root_module = b.createModule(.{
            .root_source_file = b.path("carts/suzu/bake.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .imports = imports,
        }),
    });

    const preview = b.addExecutable(.{
        .name = "suzu-preview",
        .root_module = b.createModule(.{
            .root_source_file = b.path("carts/suzu/preview.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .imports = imports,
        }),
    });
    const run_preview = b.addRunArtifact(preview);
    const wav = run_preview.addOutputFileArg("suzu-preview.wav");
    const install_wav = b.addInstallFile(wav, "suzu-preview.wav");
    b.step("suzu-preview", "Render the suzu cart's patch to zig-out/suzu-preview.wav").dependOn(&install_wav.step);

    const run = b.addRunArtifact(bake);
    const out = run.addOutputDirectoryArg("suzu-patch");
    cart.addImport("patch", b.createModule(.{ .root_source_file = out.path(b, "patch.zig") }));
    cart.addObjectFile(out.path(b, "patch.o"));
    step.dependOn(&run.step);
}
