# Contributing to Swift Package Manager
There are several types of contributions one can make. Bug fixes, documentation and enhancements that do not materially change the user facing semantics of Swift Package Manager should be submitted directly as PR.  

Larger changes that do materially change the semantics of Swift Package Manager (e.g. changes to the manifest format or behavior) are required to go through [Swift Evolution Process](https://github.com/apple/swift-evolution/blob/master/process.md).  

To see how previous evolution decisions for SwiftPM have been made and have some direction for the development of future features please check out the [Community Proposal](Documentation/Internals/PackageManagerCommunityProposal.md).  

For more information about making contributions to the Swift project in general see [Swift Contribution Guide](https://swift.org/contributing/)  

## Reporting issues
Report a bug guide: https://github.com/apple/swift-package-manager/blob/main/Documentation/Resources.md#reporting-a-good-swiftpm-bug.  
JIRA Bug Tracker (a place where you can open bugs, enhancements to start to contribute): [https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22](https://bugs.swift.org/browse/SR-13640?jql=component%20%3D%20%22Package%20Manager%22).

## Development environment
If you are contributing using macOS, the best option is to use Xcode to build and run test SwiftPM.  
You have multiple ways to setup your development environment, here we will focus on two:  
* [Using Xcode](#using-xcode)
* [Using a standalone Swift toolchain](#using-standalone)
* [Using a Trunk Snapshot](#using-trunk-snapshot)
* [Self Hosting](#self-hosting)
* [Using the Swift Compiler Build Script](#swift-compiler-build-script)

<a id="using-xcode">*A) _Use Xcode to setup what you need_*.</a>  
Xcode is only available for macOS.

1. Install latest Xcode - [https://developer.apple.com/xcode](https://developer.apple.com/xcode/)
2. Confirm you have the latest SwiftPM:
```
$> swift package --version
Swift Package Manager - Swift 5.3.0
```
3. Confirm you have the latest Swift version:
```
$> swift --version
Apple Swift version 5.3
```

<a id="using-standalone">*B) _Use standalone Swift toolchain_*</a>:  
Download the toolchain from https://swift.org/download/ (or use tools like swiftenv) and confirm its installed correctly as described above.

<a id="using-trunk-snapshot">*C) _Using a Trunk Snapshot_*</a>:  
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

<a id="self-hosting">*D) _Self Hosting_*</a>:  

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

<a id="swift-compiler-build-script">*E) _Using the Swift Compiler Build Script_*</a>:  

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

## Getting Started
1. Pull the SwiftPM repository:
```
git clone https://github.com/apple/swift-package-manager.git
```
2. Run your first build:
```
$> cd swift-package-manager
$> swift build
```
Make sure the build did not fail.  

A `.build/` folder will be generated and it should have inside a similar structure (including build binaries):
```
artifacts/
checkouts/
debug/
repositories
x86_64-apple-macosx
debug.yaml
manifest.db
workspace-state.json 
```
Binaries (in the example above) are in `x86_64-apple-macosx/`.  
If you need to build the generated binaries, run `swift-build` in inside `.build/`:
```
./.build/x86_64-apple-macosx/debug/swift-build
```

## Using Continuous Integration
SwiftPM uses [swift-ci](https://ci.swift.org) infrastructure for its continuous integration testing. The bots can be triggered on pull-requests if you have commit access. Otherwise, ask
one of the code owners to trigger them for you. The following commands are supported:

```
@swift-ci please smoke test
```

Run tests with the trunk compiler and other projects. This is **required** before
a pull-request can be merged.

```
@swift-ci please smoke test self hosted
```

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

## Commits / PRs
1. Fork: https://github.com/apple/swift-package-manager
2. Clone a working copy of your fork
3. Create a new branch
4. Make your code changes
5. Commit (include the Radar link or JIRA issue id in the commit message if possible and a description your changes)
6. Push the commit / branch to your fork
7. Make a PR from your fork / branch to `apple: main`
8. Leave a new comment to trigger smoke tests: `@swift-ci please smoke test`
9. Reviewers are going to be automatically added to your PR
10. Merge pull request when you received approval from the reviewers (one or more)

## Community and Support
If you want to connect with the Swift community you can:
* Use Swift Forums: [https://forums.swift.org/c/development/SwiftPM](https://forums.swift.org/c/development/SwiftPM)
* Contact the CODEOWNERS: https://github.com/apple/swift-package-manager/blob/main/CODEOWNERS
(mailing lists are usually the best place to go for help: [code-owners@swift.org](mailto:code-owners@swift.org), [conduct@swift.org](mailto:conduct@swift.org), [swift-infrastructure@swift.org](mailto:swift-infrastructure@swift.org)

## Additional resources
* `Swift.org` Contributing page
[https://swift.org/contributing/](https://swift.org/contributing/)
* License
[https://swift.org/LICENSE.txt](https://swift.org/LICENSE.txt)
* Code of Conduct
[https://swift.org/community/#code-of-conduct](https://swift.org/community/#code-of-conduct)

## Troubleshooting
* If during `swift build` you encounter this error:
```
/../apple-repos/swift-package-manager/.build/checkouts/swift-driver/Sources/SwiftDriver/Explicit Module Builds/InterModuleDependencyGraph.swift:102:3: error: unknown attribute '_spi'
  @_spi(Testing) public var isFramework: Bool
  ^
```
Make sure you are using SwiftPM 5.3
```
$> swift package --version
Swift Package Manager - Swift 5.3.0
```
* If during `swift build` you encounter this error:
```
/../swift-package-manager/Sources/PackageLoading/Target+PkgConfig.swift:84:36: error: type 'PkgConfigError' has no member 'prohibitedFlags'
            error = PkgConfigError.prohibitedFlags(filtered.unallowed.joined(separator: ", "))
                    ~~~~~~~~~~~~~~ ^~~~~~~~~~~~~~~
```
Make sure to update your TSC (Tools Support Core):
```
swift package update
```
Alternatively, if you are using Xcode, you can update to the latest version of all packages:  
**Xcode App** > *File* > *Swift Packages* > *Update to Latest Package Versions*
