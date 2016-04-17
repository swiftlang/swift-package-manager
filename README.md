# Swift Package Manager

The Swift Package Manager is a tool for managing distribution of source code,
aimed at making it easy to share your code and reuse others’ code. The tool
directly addresses the challenges of compiling and linking Swift packages,
managing dependencies, versioning, and supporting flexible distribution and
collaboration models.

We’ve designed the system to make it really easy to share packages on services
like GitHub, 
but packages are also great for private personal development, sharing code
within a team, or at any other granularity.

* * *

## A Work In Progress

The Swift Package Manager is still
in early design and development — we are aiming to have it stable and
ready for use with Swift 3 but currently all details are subject to change and many important features are yet to be implemented.

Additionally, it is important to note that the Swift language syntax is not stable, so packages you write will (likely) break as Swift evolves.

## Installing

The package manager is bundled with the [**Trunk Development** Snapshots available at swift.org](https://swift.org/download/). Following installation you will need to do one of the following to use the package manager on the command line:

* Xcode 7.3:

        export TOOLCHAINS=swift

* Xcode 7.2:

        export PATH=/Library/Toolchains/swift-latest.xctoolchain/usr/bin:$PATH

* Linux:

        export PATH=path/to/toolchain/usr/bin:$PATH

You can verify your installation by typing `swift build --version` in a terminal:

```sh
$ swift build --version
Apple Swift Package Manager
```

The following indicates you have not installed a snapshot successfully:

    <unknown>:0: error: no such file or directory: 'build'

### Managing Swift Environments

The `TOOLCHAINS` environment variable on OS X can be used to control which
`swift` is instantiated:

```sh
$ xcrun --find swift
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
$ swift --version
Apple Swift version 2.2
$ export TOOLCHAINS=swift
$ xcrun --find swift
/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift
$ swift --version
Swift version 3.0-dev
```

On OS X `/usr/bin/swift` is just a stub that forwards invocations to the active
toolchain. Thus when you call `swift build` it will use the swift defined by
your `TOOLCHAINS` environment variable.

To use a specific toolchain you can set `TOOLCHAINS` to the `CFBundleIdentifier`
in an `.xctoolchain`’s Info.plist.

This feature requires Xcode 7.3.


## Development

The Package Manager is itself a Swift Package and thus can be used
to build itself. However we recommend instead one of the three
following options:

1. Using the [Swift project `build-script`](https://github.com/apple/swift/blob/master/README.md):

        swift/utils/build-script --swiftpm --llbuild

2. Independently with the bootstrap script:
  1. [Download and install a Swift snapshot](https://swift.org/download)
  2. Locate its `usr/bin` directory
  3. Run the bootstrap script:

            swiftpm/Utilities/bootstrap --swiftc path/to/snapshot/usr/bin/swiftc --sbt path/to/snapshot/usr/bin/swift-build-tool

   `swiftc` and `swift-build-tool` are both executables provided as part of Swift downloadable snapshots, _they are **not** built from the sources in this repository_.

3. Using the Xcode Project in [Support](Support), this option requires:
   * Xcode 7.3 (beta)
   * [llbuild](https://github.com/apple/swift-llbuild) cloned parallel to your SwiftPM clone
  * Possibly, [a more recent Swift snapshot](https://swift.org/download)

###Choosing Swift version

The `SWIFT_EXEC` environment variable specifies the `swiftc` executable path used by `swift build`. If it is not set, SPM will try to locate it:

1. In `swift-build`'s parent directory. 
2. (on OS X) by calling `xcrun --find swiftc`
3. in PATH


There is further development-oriented documentation in [Documentation/Internals](Documentation/Internals).


## System Requirements

The package manager’s system requirements are the same as [those for Swift](https://github.com/apple/swift#system-requirements) with the caveat that the package manager requires Git at runtime as well as build-time.

## Contributing

To learn about the policies and best practices that govern
contributions to the Swift project,
please read the [Contributor Guide](https://swift.org/contributing/).

If you are interested in contributing, please read the [Community Proposal](Documentation/PackageManagerCommunityProposal.md),
which provides some context for decisions made in the current implementation and offers direction
for the development of future features.

Tests are an important part of the development and evolution of this project,
and new contributions are expected to include tests for any functionality
change.  To run the tests, pass the `test` verb to the `bootstrap` script:

    ./Utilities/bootstrap test

> Long-term, we intend for testing to be an integral part of the Package Manager itself
> and to not require custom support.

The Swift package manager uses [llbuild](https://github.com/apple/swift-llbuild) as the underlying build system
for compiling source files.  It is also open source and part of the Swift project.

## Getting Help

If you have any trouble with the package manager, help is available. We recommend:

* The [swift-users mailing list](mailto:swift-users@swift.org)
* Our [bug tracker](http://bugs.swift.org)

If you’re not comfortable sharing your question with the list, contact details for the code owners can be found in [CODE_OWNERS.txt](CODE_OWNERS.txt); however, the mailing list is usually the best place to go for help.

* * *

## Technical Overview

A thorough guide to Swift and the Package Manager is available [at swift.org](https://swift.org/package-manager/). The following is technical documentation, describing the
basic concepts that motivate the functionality of the Swift Package Manager.


### Modules

Swift organizes code into _modules_.
Each module specifies a namespace
and enforces access controls on which parts of that code
can be used outside of that module.

A program may have all of its code in a single module,
or it may import other modules as _dependencies_.
Aside from the handful of system-provided modules,
such as Darwin on OS X
or GLibc on Linux,
most dependencies require code to be downloaded and built in order to be used.

> Extracting code that solves a particular problem into a separate module
> allows for that code to be reused in other situations.
> For example, a module that provides functionality for making network requests
> could be shared between a photo sharing app
> and a program that displays the weather forecast.
> And if a new module comes along that does a better job,
> it can be swapped in easily, with minimal change.
> By embracing modularity,
> you can focus on the interesting aspects of the problem at hand,
> rather than getting bogged down solving problems you encounter along the way.

As a rule of thumb: more modules is probably better than fewer modules. The package manager is designed to make creating both packages and apps with multiple modules as easy as possible.

### Building Swift Modules

The Swift Package Manager and its build system needs to understand how to
compile your source code.  To do this, it uses a convention-based approach which
uses the organization of your source code in the file system to determine what
you mean, but allows you to fully override and customize these details.  A
simple example could be:

    foo/Package.swift
    foo/Sources/main.swift

> `Package.swift` is the manifest file that contains metadata about your package. For simple projects an empty file is OK, however the file must still exist. `Package.swift` is documented in a later section.

If you then run the following command in the directory `foo`:

```sh
swift build
```

Swift will build a single executable called `foo`.

To the package manager, everything is a package, hence `Package.swift`. However
this does not mean you have to release your software to the wider world: you can
develop your app without ever publishing it in a place where others can see or
use. On the other hand, if one day you decide that your project _should_ be 
available to a wider audience your sources are already in a form ready to be
published.  The package manager is also independent of specific forms of
distribution, so you can use it to share code within your personal projects,
within your workgroup, team or company, or with the world.

Of course, the package manager is used to build itself, so its own source files
are laid out following these conventions as well.

> [Further Reading: Source Layouts](Documentation/SourceLayouts.md)

Please note that currently we only build static libraries. In general this has benefits, however we understand the need for dynamic libraries and support for this will be added in due course.

### Packages & Dependency Management

Modern development is accelerated by
the exponential use of external dependencies (for better and worse).  This is
great for allowing you to get more done with less time, but adding dependencies
to a project has an associated coordination cost.

In addition to downloading and building the source code for a dependency,
that dependency's own dependencies must be downloaded and built as well,
and so on, until the entire dependency graph is satisfied.
To complicate matters further,
a dependency may specify version requirements,
which may have to be reconciled with the version requirements
of other modules with the same dependency.

The role of the package manager is to automate the process
of downloading and building all of the dependencies for a project,
and minimize the coordination costs associated with code reuse.

Dependencies are specified in your `Package.swift` manifest file.

> [Further Reading: Package.swift — The Manifest File](Documentation/Package.swift.md)
 
> [Further Reading: Developing Packages](Documentation/DevelopingPackages.md)

### Using System Libraries

Your platform comes with a wealth of rich and powerful C libraries installed via the system package manager. Your Swift code can use them.

> [Further Reading: System Modules](Documentation/SystemModules.md)

## License

Copyright 2015 - 2016 Apple Inc. and the Swift project authors.
Licensed under Apache License v2.0 with Runtime Library Exception.

See https://swift.org/LICENSE.txt for license information.

See https://swift.org/CONTRIBUTORS.txt for Swift project authors.
