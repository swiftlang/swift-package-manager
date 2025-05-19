# Setting the build configuration for Swift package

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

SwiftPM allows two build configurations: Debug (default) and Release.

### Debug

By default, running `swift build` will build in its debug configuration.
Alternatively, you can also use `swift build -c debug`. The build artifacts are
located in a directory called `debug` under the build folder. A Swift target is built
with the following flags in debug mode:

* `-Onone`: Compile without any optimization.
* `-g`: Generate debug information.
* `-enable-testing`: Enable the Swift compiler's testability feature.

A C language target is built with the following flags in debug mode:

* `-O0`: Compile without any optimization.
* `-g`: Generate debug information.

### Release

To build in release mode, type `swift build -c release`. The build artifacts
are located in directory named `release` under the build folder. A Swift target is
built with following flags in release mode:

* `-O`: Compile with optimizations.
* `-whole-module-optimization`: Optimize input files (per module) together
  instead of individually.

A C language target is built with following flags in release mode:

* `-O2`: Compile with optimizations.

### Additional Flags

You can pass more flags to the C, C++, or Swift compilers in three different ways:

* Command-line flags passed to these tools: flags like `-Xcc` or `-Xswiftc` are used to
  pass C or Swift flags to all targets, as shown with `-Xlinker` above.
* Target-specific flags in the manifest: options like `cSettings` or `swiftSettings` are
  used for fine-grained control of compilation flags for particular targets.
* A destination JSON file: once you have a set of working command-line flags that you
  want applied to all targets, you can collect them in a JSON file and pass them in through
  `extra-cc-flags` and `extra-swiftc-flags` with `--destination example.json`. Take a
  look at `Utilities/build_ubuntu_cross_compilation_toolchain` for an example.

One difference is that C flags passed in the `-Xcc` command-line or manifest's `cSettings`
are supplied to the Swift compiler too for convenience, but `extra-cc-flags` aren't.
