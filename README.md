[![CI](https://github.com/allyourcodebase/libffi/actions/workflows/ci.yaml/badge.svg)](https://github.com/allyourcodebase/libffi/actions)

# libffi

This is [libffi](https://sourceware.org/libffi/), packaged for [Zig](https://ziglang.org/).

## Installation

First, update your `build.zig.zon`:

```
# Initialize a `zig build` project if you haven't already
zig init
zig fetch --save git+https://github.com/allyourcodebase/libffi.git
```

You can then import `libffi` in your `build.zig` with:

```zig
const libffi = b.dependency("libffi", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.linkLibrary(libffi.artifact("ffi"));
```
