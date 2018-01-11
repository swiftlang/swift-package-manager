# Development

This document contains information on building and testing the Swift Package Manager.

## Using Swift compiler build script

The official way to build and test is using the Swift compiler build script.
First, follow the instructions provided
[here](https://github.com/apple/swift/blob/master/README.md#getting-started) and
then run one of these commands from the Swift Package Manager directory:

##### macOS:

```sh
$ ../swift/utils/build-script -R --llbuild --swiftpm
```

##### Linux:

```sh
$ ../swift/utils/build-script -R --llbuild --swiftpm --xctest --foundation --libdispatch
```

This will build compiler and friends in `build/` directory. It takes about ~1
hour for the initial build process. However, it is not really required to build
the entire compiler in order to work on the Package Manager. A faster option is
using a [snapshot](https://swift.org/download/#releases) from swift.org.

## Using trunk snapshot


1. [Download](https://swift.org/download/#releases) and install latest Trunk Development snapshot.
2. Run the following command depending on your platform.


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
 
3. Building the Swift Package Manager.

	```sh
	$ cd swiftpm
	$ Utilities/bootstrap
	```
	
    This command will build the Package Manager inside `.build/` directory.
    Run the bootstrap script to rebuild after making a change to the source
    code.
	
    You can also use the built binaries: `swift-build`, `swift-package`,
    `swift-test`, `swift-run`.
	
	
	### Example:
	```sh
	$ cd /tmp && mkdir hello && cd hello
	$ /path/to/swiftpm/.build/x86_64-apple-macosx10.10/debug/swift-package init
	$ /path/to/swiftpm/.build/x86_64-apple-macosx10.10/debug/swift-build
	```
	

4. Testing the Swift Package Manager.

	```sh
	$ Utilities/bootstrap test --test-parallel
	```
	Use this command to run the tests. All tests must pass before a patch can be accepted.
	

## Self-hosting

It is possible to build the Package Manager with itself. This is useful when you
want to rebuild just the sources or run a single test. Make sure you run the
bootstrap script first.

```sh
$ cd swiftpm

# Rebuild just the sources.
$ .build/x86_64-apple-macosx10.10/debug/swift-build

# Run a single test.
$ .build/x86_64-apple-macosx10.10/debug/swift-test --filter BasicTests.GraphAlgorithmsTests/testCycleDetection
```

Note: If you make any changes to `PackageDescription` or `PackageDescription4`
target, you **will** need to rebuild using the bootstrap script.

## Developing using Xcode

Run the following command to generate a Xcode project.

```sh
$ Utilities/bootstrap --generate-xcodeproj
generated: ./SwiftPM.xcodeproj
$ open SwiftPM.xcodeproj
```

Note: If you make any changes to `PackageDescription` or `PackageDescription4`
target, you will need to regenerate the Xcode project using the above command.

## Running the performance tests

Running performance tests is a little awkward right now. First, generate the
Xcode project using this command.

```sh
$ Utilities/bootstrap --generate-xcodeproj --enable-perf-tests
```

Then, open the generated project and run the `PerformanceTest` scheme.

## Testing on Linux with Docker

For contributors on macOS who need to test on Linux, install Docker and use the
following commands:

```sh
$ Utilities/docker-utils build # will build an image with the latest swift snapshot
$ Utilities/docker-utils bootstrap # will bootstrap SwiftPM on the linux container
$ Utilities/docker-utils run bash # to run an interactive bash shell in the container
$ Utilities/docker-utils swift-build # to run swift-build in the container
$ Utilities/docker-utils swift-test # to run swift-test in the container
$ Utilities/docker-utils swift-run # to run swift-run in the container
```

## Using custom Swift compilers

SwiftPM needs Swift compiler to parse Package.swift manifest files and to
compile Swift source files. You can use `SWIFT_EXEC` and `SWIFT_EXEC_MANIFEST`
environment variables to control which compiler to use for these operations.

`SWIFT_EXEC_MANIFEST`: This variable controls which compiler to use for parsing
Package.swift manifest files. The lookup order for manifest compiler is:
SWIFT_EXEC_MANIFEST, swiftc adjacent to swiftpm binaries, SWIFT_EXEC

`SWIFT_EXEC`: This variable controls which compiler to use for compiling Swift
sources. The lookup order for manifest compiler is: SWIFT_EXEC, swiftc adjacent
to swiftpm binaries. This is also useful for Swift compiler developers when they
want to use a debug compiler with SwiftPM.

```sh
$ SWIFT_EXEC=/path/to/my/built/swiftc swift build
```
