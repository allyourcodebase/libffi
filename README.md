# libffi zig

[libffi](https://github.com/libffi/libffi), packaged for the Zig build system.

Supports x86_64, x86, aarch64, and arm on Linux, macOS, and BSDs.

## Using

First, update your `build.zig.zon`:

```
zig fetch --save git+https://github.com/allyourcodebase/libffi.git
```

Then in your `build.zig`:

```zig
const libffi = b.dependency("libffi", .{ .target = target, .optimize = optimize });
exe.linkLibrary(libffi.artifact("ffi"));
```
