const std = @import("std");
const LinkMode = std.builtin.LinkMode;

const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arch = target.result.cpu.arch;
    const os = target.result.os.tag;

    const options = .{
        .linkage = b.option(LinkMode, "linkage", "Library linkage type") orelse
            .static,
    };

    const upstream = b.dependency("libffi_c", .{});
    const src = upstream.path("");

    const arch_dir, const target_name, const arch_srcs: []const []const u8, const arch_asm: []const []const u8 = switch (arch) {
        .x86_64 => .{ "src/x86", "X86_64", &.{ "src/x86/ffi64.c", "src/x86/ffiw64.c" }, if (os == .windows) &.{"src/x86/win64.S"} else &.{ "src/x86/unix64.S", "src/x86/win64.S" } },
        .x86 => .{ "src/x86", "X86", &.{"src/x86/ffi.c"}, &.{"src/x86/sysv.S"} },
        .aarch64 => .{ "src/aarch64", "AARCH64", &.{"src/aarch64/ffi.c"}, &.{"src/aarch64/sysv.S"} },
        .arm => .{ "src/arm", "ARM", &.{"src/arm/ffi.c"}, &.{"src/arm/sysv.S"} },
        else => return,
    };

    const ffi_h = b.addConfigHeader(.{
        .style = .{ .autoconf_at = upstream.path("include/ffi.h.in") },
        .include_path = "ffi.h",
    }, .{
        .VERSION = manifest.version,
        .TARGET = target_name,
        .HAVE_LONG_DOUBLE = 1,
        .FFI_EXEC_TRAMPOLINE_TABLE = @as(i64, if (os == .macos and arch == .aarch64) 1 else 0),
        .FFI_VERSION_STRING = manifest.version,
        .FFI_VERSION_NUMBER = 30502,
    });

    const config_wf = b.addWriteFiles();
    _ = config_wf.add("fficonfig.h", b.fmt(
        \\#ifndef LIBFFI_CONFIG_H
        \\#define LIBFFI_CONFIG_H
        \\#define HAVE_LONG_DOUBLE 1
        \\#define STDC_HEADERS 1
        \\#define HAVE_INTTYPES_H 1
        \\#define HAVE_STDINT_H 1
        \\#define HAVE_STRING_H 1
        \\{s}{s}{s}{s}{s}{s}
        \\#ifdef HAVE_HIDDEN_VISIBILITY_ATTRIBUTE
        \\#ifdef LIBFFI_ASM
        \\#ifdef __APPLE__
        \\#define FFI_HIDDEN(name) .private_extern name
        \\#else
        \\#define FFI_HIDDEN(name) .hidden name
        \\#endif
        \\#else
        \\#define FFI_HIDDEN __attribute__ ((visibility ("hidden")))
        \\#endif
        \\#else
        \\#ifdef LIBFFI_ASM
        \\#define FFI_HIDDEN(name)
        \\#else
        \\#define FFI_HIDDEN
        \\#endif
        \\#endif
        \\#endif
        \\
    , .{
        if (os == .linux or os == .macos) "#define HAVE_ALLOCA_H 1\n" else "",
        if (os != .linux and os != .windows) "#define HAVE_HIDDEN_VISIBILITY_ATTRIBUTE 1\n" else "",
        if (os != .linux) "#define HAVE_MMAP 1\n#define HAVE_MPROTECT 1\n#define FFI_MMAP_EXEC_WRIT 1\n" else "",
        if (os == .linux) "#define HAVE_MEMFD_CREATE 1\n#define HAVE_SYS_MEMFD_H 1\n" else "",
        if (os == .linux) "#define FFI_EXEC_STATIC_TRAMP 1\n" else "",
        if (arch == .x86_64 or arch == .x86) "#define HAVE_AS_X86_PCREL 1\n" else "",
    }));

    const flags: []const []const u8 = &.{if (os != .windows) "-fvisibility=hidden" else ""};

    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addConfigHeader(ffi_h);
    mod.addIncludePath(config_wf.getDirectory());
    mod.addIncludePath(upstream.path("include"));
    mod.addIncludePath(upstream.path(arch_dir));
    mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = srcs });
    mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = arch_srcs });
    for (arch_asm) |asm_file| mod.addAssemblyFile(src.path(b, asm_file));

    const lib = b.addLibrary(.{
        .name = "ffi",
        .root_module = mod,
        .linkage = options.linkage,
        .version = try .parse(manifest.version),
    });
    lib.installConfigHeader(ffi_h);
    lib.installHeader(upstream.path(b.pathJoin(&.{ arch_dir, "ffitarget.h" })), "ffitarget.h");
    b.installArtifact(lib);
}

const srcs: []const []const u8 = &.{
    "src/prep_cif.c",     "src/types.c",    "src/raw_api.c",
    "src/java_raw_api.c", "src/closures.c", "src/tramp.c",
};
