# Swift Package Manager Project

The Swift Package Manager is a tool for managing distribution of source code, aimed at making it easy to share your code and reuse others’ code. The tool directly addresses the challenges of compiling and linking Swift packages, managing dependencies, versioning, and supporting flexible distribution and collaboration models.

We’ve designed the system to make it easy to share packages on services like GitHub, but packages are also great for private personal development, sharing code within a team, or at any other granularity.

Note that at this time the Package Manager has no support for iOS, watchOS, or tvOS platforms.

---

## Table of Contents

* [Contributions](#contributions)
* [System Requirements](#system-requirements)
* [Installation](#installation)
  * [Managing Swift Environments](#managing-swift-environments)
  * [Choosing a Swift Version](#choosing-a-swift-version)
* [Documentation](#documentation)
* [Support](#support)
* [License](#license)

---

## Contributions

To learn about the policies and best practices that govern contributions to the Swift project, please read the [Contributor Guide](https://swift.org/contributing/).

If you are interested in contributing, please read the [Community Proposal](Documentation/PackageManagerCommunityProposal.md), which provides some context for decisions made in the current implementation and offers direction for the development of future features.

Instructions for setting up the development environment are available [here](Documentation/Development.md).

The Swift package manager uses [llbuild](https://github.com/apple/swift-llbuild) as the underlying build system for compiling source files.  It is also open source and part of the Swift project.

---

## System Requirements

The package manager’s system requirements are the same as [those for Swift](https://github.com/apple/swift#system-requirements) with the caveat that the package manager requires Git at runtime as well as build-time.

---

## Installation

The Swift Package Manager is included in Xcode 8.0 and all subsequent release.

The package manager is also available for other platforms as part of all [Snapshots available at swift.org](https://swift.org/download/), including snapshots for the latest versions built from `master`. For installation instructions for downloaded snapshots, please see the [Getting Started](https://swift.org/getting-started/#installing-swift) section of [swift.org](https://swift.org).

You can verify your installation by typing `swift package --version` in a terminal:

```sh
$ swift package --version
Apple Swift Package Manager - ...
```

### Managing Swift Environments

On macOS `/usr/bin/swift` is just a stub that forwards invocations to the active
toolchain. Thus when you call `swift build` it will use the swift defined by
your `TOOLCHAINS` environment variable. This can be used to easily switch
between the default tools, and a development snapshot:

```sh
$ xcrun --find swift
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
$ swift --version
Apple Swift version 3.0
$ export TOOLCHAINS=swift
$ xcrun --find swift
/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
$ swift --version
Swift version 3.0-dev
```

To use a specific toolchain you can set `TOOLCHAINS` to the `CFBundleIdentifier` in an `.xctoolchain`’s Info.plist.

### Choosing a Swift Version

The `SWIFT_EXEC` environment variable specifies the `swiftc` executable path used by `swift package`. If it is not set, the package manager will try to locate it:

1. In `swift-package`'s parent directory.
2. On macOS, by calling `xcrun --find swiftc`.
3. By searching the PATH.

---

## Documentation

For extensive documentation on using Swift Package Manager, creating packages, and more, see [Documentation](Documentation).

For additional documentation on developing the Swift Package Manager itself, see [Documentation/Internals](Documentation/Internals).

---

## Support

If you have any trouble with the package manager, help is available. We recommend:

* The [swift-users mailing list](mailto:swift-users@swift.org)
* Our [bug tracker](http://bugs.swift.org)

If you’re not comfortable sharing your question with the list, contact details for the code owners can be found in [CODE_OWNERS.txt](CODE_OWNERS.txt); however, the mailing list is usually the best place to go for help.

---

## License

Copyright 2015 - 2016 Apple Inc. and the Swift project authors. Licensed under Apache License v2.0 with Runtime Library Exception.

See [https://swift.org/LICENSE.txt](https://swift.org/LICENSE.txt) for license information.

See [https://swift.org/CONTRIBUTORS.txt](https://swift.org/CONTRIBUTORS.txt) for Swift project authors.
