# Getting Started

// FIXME: First time user swift package init and get something running
run the tool and get anything working


// FIXME: remove this vvvvv

## Testing

Use the `swift test` tool to run the tests of a Swift package. For more information on the test tool, run `swift test --help`.

## Running

Use the `swift run [executable [arguments...]]` tool to run an executable product of a Swift
package. The executable's name is optional when running without arguments and when there
is only one executable product. For more information on the run tool, run
`swift run --help`.

## Setting the Build Configuration

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

<!-- TODO: maybe in a topic about cross compilation -->

You can pass more flags to the C, C++, or Swift compilers in three different ways:

- Command-line flags passed to these tools: flags like `-Xcc` or `-Xswiftc` are used to
  pass C or Swift flags to all targets, as shown with `-Xlinker` above.
- Target-specific flags in the manifest: options like `cSettings` or `swiftSettings` are
  used for fine-grained control of compilation flags for particular targets.
