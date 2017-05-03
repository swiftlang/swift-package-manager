# Development

This document contains information on building and testing the Swift Package Manager.

## Using Swift compiler build script

The official way to build and test is using the Swift compiler build script.
First, follow the instructions provided
[here](https://github.com/apple/swift/blob/master/README.md#getting-started) and
then run one of these commands:

##### macOS:

```sh
$ swift/utils/build-script -R --llbuild --swiftpm
```

##### Linux:

```sh
$ swift/utils/build-script -R --llbuild --swiftpm --xctest --foundation --libdispatch
```

This will build compiler and friends in `build/` directory. It takes about ~1
hour for the inital build process. However, it is not really required to build
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
    `swift-test`.
	
	
	### Example:
	```sh
	$ cd /tmp && mkdir hello && cd hello
	$ /path/to/swiftpm/.build/debug/swift-package init
	$ /path/to/swiftpm/.build/debug/swift-build
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
$ .build/debug/swift-build

# Run a single test.
$ .build/debug/swift-test -s BasicTests.GraphAlgorithmsTests/testCycleDetection
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
