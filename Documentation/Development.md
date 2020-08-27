# Development

This document contains information on building and testing the Swift Package
Manager. There are many ways to develop Swift Package Manager. The official way
is to use Swift's build-script which builds the full compiler toolchain but
that's rarely required.

## Using the Swift Compiler Build Script

Follow [these](https://github.com/apple/swift#getting-started) instructions to
get the Swift sources and then execute the `build-script` using swiftpm preset:

### macOS

```sh
$ ./swift/utils/build-script --preset=buildbot_swiftpm_macos_platform,tools=RA,stdlib=RA
```

### Linux

```sh
$ ./swift/utils/build-script --preset=buildbot_swiftpm_linux_platform,tools=RA,stdlib=RA
```

Once the build is complete, you should be able to run the swiftpm binaries from the build folder.

## Developing using Xcode

Simply open SwiftPM's `Package.swift` manifest with the latest release (including betas) of Xcode.

Note: PackageDescription v4 is not available when developing using this method.

You can also run SwiftPM performance tests in Xcode using the SwiftPM-Perf
scheme.

## Self Hosting

It is possible to build SwiftPM with itself using SwiftPM present in latest
release of Xcode or the latest trunk snapshot on Linux.

```sh
# Build:
$ swift build

# Run all tests.
$ swift test --parallel

# Run a single test.
$ swift test --filter PackageGraphTests.DependencyResolverTests/testBasics

# Run tests for the test targets BuildTests and WorkspaceTests, but skip some test cases.
$ swift test --filter BuildTests --skip BuildPlanTests --filter WorkspaceTests --skip InitTests
```

Note: PackageDescription v4 is not available when developing using this method.

This method can also used be used for performance testing. Use the following
command run SwiftPM's performance tests:

```
$ export TSC_ENABLE_PERF_TESTS=1
$ swift test -c release --filter PerformanceTests
```

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

4. Clone [Yams](https://github.com/jpsim/yams) beside the package manager directory.

```sh
$ git clone https://github.com/jpsim/yams
```

5. Clone [swift-driver](https://github.com/apple/swift-driver) beside the package manager directory.

```sh
$ git clone https://github.com/apple/swift-driver
```

6. Clone [swift-argument-parser](https://github.com/apple/swift-argument-parser) beside the package manager directory and check out tag 0.3.0.

```sh
$ git clone https://github.com/apple/swift-argument-parser --branch 0.3.0
```

7. Build the Swift Package Manager.

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

8. Test the Swift Package Manager.

```sh
$ Utilities/bootstrap test
```

## Using Continuous Integration

SwiftPM uses [swift-ci](https://ci.swift.org) infrastructure for its continuous integration testing. The
bots can be triggered on pull-requests if you have commit access. Otherwise, ask
one of the code owners to trigger them for you. The following commands are supported:

    @swift-ci please smoke test

Run tests with the trunk compiler and other projects. This is **required** before
a pull-request can be merged.

    @swift-ci please smoke test self hosted

Run just the self-hosted tests. This has fast turnaround times so it can be used
to get quick feedback.

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

## Making changes in TSC targets

All targets with the prefix TSC define the interface for the tools support core. Those APIs might be used in other projects as well and need to be updated in this repository by copying their sources directories to the TSC repository. The repository can be found [here](https://github.com/apple/swift-tools-support-core).
