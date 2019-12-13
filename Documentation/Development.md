# Development

This document contains information on building and testing the Swift Package Manager.

## Using the Swift Compiler Build Script

The official way to build and test is using the Swift compiler build script.
First, follow the instructions provided
[here](https://github.com/apple/swift/blob/master/README.md#getting-started) and
then run one of these commands from the Swift Package Manager directory:

### macOS

```sh
$ ../swift/utils/build-script -R --llbuild --swiftpm
```

### Linux

```sh
$ ../swift/utils/build-script -R --llbuild --swiftpm --xctest --foundation --libdispatch
```

This will build the compiler and friends in the `build/` directory. It takes about 1
hour for the initial build process. However, it is not really required to build
the entire compiler in order to work on the Package Manager. A faster option is
using a [snapshot](https://swift.org/download/#releases) from swift.org.

## Using a Trunk Snapshot

1. [Download](https://swift.org/download/#snapshots) and install the latest Trunk Development snapshot.
2. Run the following commands depending on your platform.

### macOS

```sh
$ export TOOLCHAINS=swift
# Verify that we're able to find the swift compiler from the installed toolchain.
$ xcrun --find swift
/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
```

### Linux

```sh
$ export PATH=/path/to/swift-toolchain/usr/bin:"${PATH}"
# Verify that we're able to find the swift compiler from the installed toolchain.
$ which swift
/path/to/swift-toolchain/usr/bin/swift
```

3. Clone [llbuild](https://github.com/apple/swift-llbuild) beside the package manager directory.

```sh
$ git clone https://github.com/apple/swift-llbuild llbuild
$ ls
swiftpm llbuild
```

Note: Make sure the directory for llbuild is called "llbuild" and not
    "swift-llbuild".

4. Build the Swift Package Manager.

```sh
$ cd swiftpm
$ Utilities/bootstrap build
```

 Note: The bootstrap script requires having [CMake](https://cmake.org/) and [Ninja](https://ninja-build.org/) installed. Please refer to the [Swift project repo](https://github.com/apple/swift/blob/master/README.md#macos) for installation instructions.

This command builds the Package Manager inside the `.build/` directory.
    Run the bootstrap script to rebuild after making a change to the source
    code.

### Example

```sh
$ cd /tmp && mkdir hello && cd hello
$ /path/to/swiftpm/.build/x86_64-apple-macosx/debug/swift-package init
$ /path/to/swiftpm/.build/x86_64-apple-macosx/debug/swift-build
```

5. Test the Swift Package Manager.

```sh
$ Utilities/bootstrap test
```

Use this command to run the tests. All tests must pass before a patch can be accepted.

## Self Hosting a Swift Package

It is possible to build SwiftPM with itself using the built SwiftPM
 binaries. This is useful when you want to rebuild just the
sources or run a single test. Make sure you run the bootstrap script first.

```sh
$ cd swiftpm

# Rebuild just the sources.
$ .build/x86_64-apple-macosx/debug/swift-build

# Run a single test.
$ .build/x86_64-apple-macosx/debug/swift-test --filter PackageGraphTests.DependencyResolverTests/testBasics
```

Note: If you make any changes to the `PackageDescription4` target, you **will**
need to rebuild using the bootstrap script.

## Developing using Xcode

Simply open SwiftPM's `Package.swift` manifest with the latest release of Xcode.
Make sure you have run `Utilites/bootstrap` beforehand.

Note: If you make any changes to the `PackageDescription4` target, you will need
to run `bootstrap` again.

## Using Continuous Integration

SwiftPM uses [swift-ci](https://ci.swift.org) infrastructure for its continuous integration testing. The
bots can be triggered on pull-requests if you have commit access. Otherwise, ask
one of the code owners to trigger them for you. The following commands are supported:

    @swift-ci please smoke test

Run tests with the trunk compiler and other projects. This is **required** before
a pull-request can be merged.

    @swift-ci test with toolchain

Run tests with the latest trunk snapshot. This has fast turnaround times so it can
be used to get quick feedback.

Note: Smoke tests are still required for merging pull-requests.

## Testing on Linux with Docker

For contributors on macOS who need to test on Linux, install Docker and use the
following commands:

```sh
$ Utilities/Docker/docker-utils build # will build an image with the latest Swift snapshot
$ Utilities/Docker/docker-utils bootstrap # will bootstrap SwiftPM on the Linux container
$ Utilities/Docker/docker-utils run bash # to run an interactive Bash shell in the container
$ Utilities/Docker/docker-utils swift-build # to run swift-build in the container
$ Utilities/Docker/docker-utils swift-test # to run swift-test in the container
$ Utilities/Docker/docker-utils swift-run # to run swift-run in the container
```

## Using Custom Swift Compilers

SwiftPM needs the Swift compiler to parse `Package.swift` manifest files and to
compile Swift source files. You can use the `SWIFT_EXEC` and `SWIFT_EXEC_MANIFEST`
environment variables to control which compiler to use for these operations.

`SWIFT_EXEC_MANIFEST`: This variable controls which compiler to use for parsing
`Package.swift` manifest files. The lookup order for the manifest compiler is:
`SWIFT_EXEC_MANIFEST`, `swiftc` adjacent to the `swiftpm` binaries, then `SWIFT_EXEC`

`SWIFT_EXEC`: This variable controls which compiler to use for compiling Swift
sources. The lookup order for the sources' compiler is: `SWIFT_EXEC`, then `swiftc` adjacent
to `swiftpm` binaries. This is also useful for Swift compiler developers when they
want to use a debug compiler with SwiftPM.

```sh
$ SWIFT_EXEC=/path/to/my/built/swiftc swift build
```

## Overriding the Path to the Runtime Libraries

SwiftPM computes the path of its runtime libraries relative to where it is
installed. This path can be overridden by setting the environment variable
`SWIFTPM_PD_LIBS` to a directory containing the libraries, or a colon-separated list of
absolute search paths. SwiftPM will choose the first
path which exists on disk. If none of the paths are present on disk, it will fall
back to built-in computation.

## Skipping SwiftPM tests

SwiftPM has a hidden env variable `_SWIFTPM_SKIP_TESTS_LIST` that can be used
to skip a list of tests. This value of the variable is either a file path that contains a
newline separated list of tests to skip, or a colon-separated list of tests.

This is only a development feature and should be considered _unsupported_.

## Making changes in TSC targets

All targets with the prefix TSC define the interface for the tools support core. Those APIs might be used in other projects as well and need to be updated in this repository by copying their sources directories to the TSC repository. The repository can be found [here](https://github.com/apple/swift-tools-support-core).
