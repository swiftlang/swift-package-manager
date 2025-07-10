# Using build configurations

Control the build configuration for your app or package.

## Overview

Package manager supports two general build configurations: Debug (default) and Release.

### Debug

By default, running `swift build` builds the package using its debug configuration.
Alternatively, you can use `swift build -c debug`.
Package manager locates the build artifacts in a directory called `debug` under the `.build` folder.
When building in the debug configuration, a Swift target uses the following Swift compiler flags:

* `-Onone`: Compile without any optimization.
* `-g`: Generate debug information.
* `-enable-testing`: Enable the Swift compiler's testability feature.

A C language target in the debug configuration uses the following flags:

* `-O0`: Compile without any optimization.
* `-g`: Generate debug information.

### Release

To build in release mode, type `swift build -c release`. 
Package manager locates the build artifacts in a directory called `release` under the `.build` folder. 
When building in the release configuration, a Swift target uses the following Swift compiler flags:

* `-O`: Compile with optimizations.
* `-whole-module-optimization`: Optimize input files (per module) together
  instead of individually.

A C language target in the release configuration uses the following flags:

* `-O2`: Compile with optimizations.

### Additional Flags

You can pass additional flags to the C, C++, or Swift compilers in three different ways:

* Command-line flags passed to these tools: flags like `-Xcc` (for the C compiler) or `-Xswiftc` (for the Swift compiler) pass relevant flags for all targets in the manifest.

* Target-specific flags in the manifest: use options like `cSettings` or `swiftSettings` for fine-grained control of compilation flags for particular targets.

* A destination JSON file: once you have a set of working command-line flags to apply to all targets, collect them in a JSON file and pass them in through `extra-cc-flags` and `extra-swiftc-flags` with `--destination example.json`. 

One difference is that C flags passed on the `-Xcc` command-line or using a manifest's `cSettings`
are supplied to the Swift compiler tool for convenience, but `extra-cc-flags` aren't.
