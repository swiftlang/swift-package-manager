# Swift Package Manager

The Swift Package Manager provides a set of tools
for building both first and third party Swift code.

* * *

## Installing

The Swift Package Manager has been included since Swift 2.1.
To install the latest version of Swift
see the 
[Swift User Guide](https://swift.org/download/).

To check if the package manager is installed,
enter the following in a terminal:

    swift build --help

If usage information is printed; you’re ready to go.

## System Requirements

System requirements are the [same as those for Swift itself](https://github.com/apple/swift#system-requirements).

## A Work In Progress

The package manager is being open-sourced early, but has not yet had a stable release. Please consider any public interface (command-line or API) subject to change. There are many important features which are not yet implemented.

It is also important to note Swift is not yet ABI or API stable so packages you write will (likely) break as Swift evolves.

## Contributing

To learn about the policies and best practices that govern
contributions to the Swift project,
please read the [Contributor Guide](https://swift.org/contributor-guide).

Interested potential contributors should read the [Swift Package Manager Community
Proposal][https://github.com/apple/swift-package-manager/blob/master/Documentation/Package-Manager-Community-Proposal.md],
which provides some context for decisions made in the current implementation and offers direction
for the development of future features.

To build from source enter the following into a terminal:

    git clone git@github.com:apple/swift-package-manager.git swiftpm
    git clone git@github.com:apple/swift-llbuild.git llbuild
    cd swiftpm
    ./Utilities/bootstrap --build-tests

It is recommended that you develop against the latest version of Swift,
to ensure compatibility with new releases.

To run the tests on Linux:

    for x in .build/.bootstrap/bin/*-test; do $x; done

On Mac use the provided Xcode project.

> Long-term, we intend for testing to be an integral part of the Package Manager itself
> and to not require custom support.

Contributions are expected to come with tests that verify the new or changed functionality.

* * *

## Overview

This section describes the basic concepts that motivate
the functionality of the Swift Package Manager.

There is a thorough guide to Swift and the Package Manager [at swift.org](https://swift.org/getting-started/). The following is technical documentation.

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

As a rule of thumb: more modules is probably better than less modules. The package manager is designed to make creating both packages and apps with multiple modules as easy as possible.

### Building Swift Modules

To facilitate rapid development, modules are computed based on how you lay out your sources. A simple example could be:

    foo/Package.swift
    foo/Sources/main.swift

> `Package.swift` is the manifest file that contains metadata about your package. For simple projects an empty file is OK, however the file must still exist. `Package.swift` is documented in a later section.

If you then run the following command in the directory `foo`:

    $ swift build

Swift will build a single executable called `foo`.

To the package manager, everything is a package, hence `Package.swift`. However this does not mean you have to release your software to the wider world as a package: you can develop your app and never consider it a package that others will see or use. On the other hand if one day you decide that your project _should_ be a package (available to the wider world or just your company’s engineers) your sources are already in a form ready to be published.

The package manager sources are laid out following these conventions and thus the package manager is used to build itself.

> [Further Reading: Source Layouts](Documentation/SourceLayouts.md)

Please note that currently we only build static libraries. In general this has benefits, however we understand the need for dynamic libraries and support for this will be added in due course.

### Packages & Dependency Management

Modern development (for better and worse) is accelerated by
the exponential use of external dependencies.

Adding dependencies to a project, however, has an associated coordination cost.
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

## Getting Help

If you have any trouble with the package manager; we want to help. Choose the option that suits you best:

* [The mailing list](mailto:swift-package-manager@swift.org)
* [The bug tracker](http://jira.swift.org)
* You can also email the code owners directly; their contact details can be found in [CODE_OWNERS.txt](CODE_OWNERS.txt).

## License

Copyright 2015 Apple Inc. and the Swift project authors.
Licensed under Apache License v2.0 with Runtime Library Exception.

See http://swift.org/LICENSE.txt for license information.

See http://swift.org/CONTRIBUTORS.txt for Swift project authors.
