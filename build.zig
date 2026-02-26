const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Library linkage type") orelse .static;

    const upstream = b.dependency("upstream", .{});
    const src = upstream.path("");
    const arch = target.result.cpu.arch;
    const os = target.result.os.tag;
    const is_linux = os == .linux;
    const is_posix = is_linux or os.isBSD();

    const arch_dir: []const u8 = switch (arch) {
        .x86_64, .x86 => "src/x86",
        .aarch64 => "src/aarch64",
        .arm => "src/arm",
        else => return error.UnsupportedArch,
    };

    const target_name: []const u8 = switch (arch) {
        .x86_64 => "X86_64",
        .x86 => "X86",
        .aarch64 => "AARCH64",
        .arm => "ARM",
        else => return error.UnsupportedArch,
    };

    // ffi.h (autoconf @VARIABLE@ substitution of upstream ffi.h.in)
    const ffi_h = b.addConfigHeader(.{
        .style = .{ .autoconf_at = upstream.path("include/ffi.h.in") },
        .include_path = "ffi.h",
    }, .{
        .VERSION = manifest.version,
        .TARGET = target_name,
        .HAVE_LONG_DOUBLE = 1,
        .FFI_EXEC_TRAMPOLINE_TABLE = 0,
        .FFI_VERSION_STRING = manifest.version,
        .FFI_VERSION_NUMBER = 30502,
    });

    // fficonfig.h (generated via WriteFile for the FFI_HIDDEN macro block)
    const config_wf = b.addWriteFiles();
    _ = config_wf.add("fficonfig.h", b.fmt(
        \\#ifndef LIBFFI_CONFIG_H
        \\#define LIBFFI_CONFIG_H
        \\
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\
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
        \\
        \\#endif
        \\
    , .{
        "#define HAVE_LONG_DOUBLE 1",
        "#define STDC_HEADERS 1",
        "#define HAVE_ALLOCA_H 1",
        "#define HAVE_INTTYPES_H 1",
        "#define HAVE_STDINT_H 1",
        "#define HAVE_STRING_H 1",
        if (is_posix) "#define HAVE_HIDDEN_VISIBILITY_ATTRIBUTE 1" else "",
        if (is_posix) "#define HAVE_MMAP 1" else "",
        if (is_posix) "#define HAVE_MPROTECT 1" else "",
        if (is_linux) "#define HAVE_MEMFD_CREATE 1" else "",
        if (is_posix) "#define FFI_MMAP_EXEC_WRIT 1" else "",
        if (is_linux) "#define FFI_EXEC_STATIC_TRAMP 1" else "",
        if (arch == .x86_64 or arch == .x86) "#define HAVE_AS_X86_PCREL 1" else "",
    }));

    // Module
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addConfigHeader(ffi_h);
    mod.addIncludePath(config_wf.getDirectory());
    mod.addIncludePath(src.path(b, "include"));
    mod.addIncludePath(src.path(b, arch_dir));

    const flags: []const []const u8 = &.{"-fvisibility=hidden"};

    mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = &.{
        "src/prep_cif.c",
        "src/types.c",
        "src/raw_api.c",
        "src/java_raw_api.c",
        "src/closures.c",
        "src/tramp.c",
    } });

    switch (arch) {
        .x86_64 => {
            mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = &.{ "src/x86/ffi64.c", "src/x86/ffiw64.c" } });
            mod.addAssemblyFile(src.path(b, "src/x86/unix64.S"));
            mod.addAssemblyFile(src.path(b, "src/x86/win64.S"));
        },
        .x86 => {
            mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = &.{"src/x86/ffi.c"} });
            mod.addAssemblyFile(src.path(b, "src/x86/sysv.S"));
        },
        .aarch64 => {
            mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = &.{"src/aarch64/ffi.c"} });
            mod.addAssemblyFile(src.path(b, "src/aarch64/sysv.S"));
        },
        .arm => {
            mod.addCSourceFiles(.{ .root = src, .flags = flags, .files = &.{"src/arm/ffi.c"} });
            mod.addAssemblyFile(src.path(b, "src/arm/sysv.S"));
        },
        else => return error.UnsupportedArch,
    }

    // Library
    const lib = b.addLibrary(.{ .name = "ffi", .root_module = mod, .linkage = linkage });
    lib.installConfigHeader(ffi_h);
    lib.installHeader(src.path(b, b.pathJoin(&.{ arch_dir, "ffitarget.h" })), "ffitarget.h");
    b.installArtifact(lib);
}
