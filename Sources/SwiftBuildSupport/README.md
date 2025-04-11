# Swift Build System Support

There is experimental support for using Swift Build as the build system for SwiftPM. You can try the build system with the `--build-system` option like this:

```
swift build --build-system=swiftbuild
```

What works so far:
* Builds on macOS
* Simple packages

Work is continuing in these areas:
* Builds on Linux and Windows
* Conditional target dependencies (i.e. dependencies that are conditional on ".when()" specific platforms)
* Plugin support
* Friendly Error and Warning Descriptions and Fixups
* Cross compiling Swift SDK's (e.g. Static Linux SDK, and Wasm with WASI)
* Improvements to test coverage
* Task execution reporting

## Problem Reporting

When raising an issue with problems regarding the Swift Build System, please indicate that you are using this build system instead of the built-in native (or xcode) build systems. Including a minimal package that exhibits the bad behaviour will help with problem diagnosis and fixing.
