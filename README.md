# Swift Package Manager

The Swift Package Manager provides a set of tools for building and distributing Swift code.

* * *

## Getting Started

(Link to "User Guide" on Swift.org)

With Swift 2.1 execute: `swift build`.
If you are developing the package manager then please
run the bootstrap script (`Utilities/bootstrap`) instead.

Swift development is iterative and rapid,
thus the package manager may require the latest Swift to compile.
If your compile fails please build the latest Swift and try again.
If you are trying to compile with the (optional) Xcode project you will need to
download a Swift xctoolchain (Link).

## Contributing

(Link to "Contributor Guide" on Swift.org)

* * *

## Overview

Swift organizes code into _modules_.
Each module specifies a namespace
and enforces access controls on which parts of that code
can be used outside of the module.

A program may have all of its code in a single module,
or it may import other modules as _dependencies_.
Aside from the handful of system-provided modules,
such as Darwin on OS X
or GLibc on Linux,
most dependencies require code to be downloaded and built in order to be used.

Extracting code that solves a particular problem into a separate module
allows for that code to be reused in other situations.
For example, a module that provides functionality for making network requests
could be shared between a photo sharing app
and a program that displays the weather forecast.
And if a new module comes along that does a better job,
it can be swapped in easily, with minimal change.
By embracing modularity, you can focus on the interesting aspects of the problem at hand,
rather than getting bogged down by solved problems you encounter along the way.

Adding dependencies to a project, however, has an associated coordination cost.
In addition to downloading and building the source code for a dependency,
that dependency's own dependencies must be downloaded and built as well,
and so on, until the entire dependency graph is satisfied.
To complicate matters further,
a dependency may specify version requirements,
which may have to be reconciled with the version requirements of another module with the same dependency.

The role of the package manager is to automate the process
of downloading and building all of dependencies for a project.

(...)

A _package_ consists of Swift source files
and a manifest file, called `Package.swift`,
which defines the package name and contents.
The `Package.swift` file defines a package in a declarative manner
with Swift code using the `PackageDescription` module.

// TODO: "You can find API documentation for the `PackageDescription` module here: ..."

A package has one or more _targets_.
Each target specifies a _product_
and may declare one or more _dependencies_.

// TODO: Should this instead say that products are modules, and not make the same distinction?
A target may build either a _library_ or an _executable_ as its product.
A library contains a module that can be imported by other Swift code.
An executable is a program that can be run by the operating system.

A target's dependencies are any modules that are required by code in the package.
A dependency consists of a relative or absolute URL
that points to the source of the package to be used,
as well as a set of requirements for what version of that code can be used.

### Convention Based Target Determination

Targets are determined automatically based on how you layout your sources.

For example if you created a directory with the following layout:

```
foo/
foo/src/bar.swift
foo/src/baz.swift
foo/Package.swift
```

Running `swift build` within directory `foo` would produce a single library target: `foo/.build/debug/foo.a`

The file `Package.swift` is the manifest file, and is discussed in the next section.

To create multiple targets create multiple subdirectories:

```
example/
example/src/foo/foo.swift
example/src/bar/bar.swift
example/Package.swift
```

Running `swift build` would produce two library targets:

* `foo/.build/debug/foo.a`
* `foo/.build/debug/bar.a`

To generate executables create a main.swift in a target directory:

```
example/
example/src/foo/main.swift
example/src/bar/bar.swift
example/Package.swift
```

Running `swift build` would now produce:

* `foo/.build/debug/foo`
* `foo/.build/debug/bar.a`

Where `foo` is an executable and `bar.a` a static library.

### Manifest File

Instructions for how to build a package are provided by
a manifest file, called `Package.swift`.
You can customize this file to
declare build targets or dependencies,
include or exclude source files,
and specify build configurations for the module or individual files.

Here's an example of a `Package.swift` file:

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    dependencies: [
        .Package(url: "ssh://git@example.com/Greeter.git", versions: "1.0.0"),
    ]
)
```

A `Package.swift` file a Swift file
that declaratively configures a Package
using types defined in the `PackageDescription` module.
This manifest declares a dependency on an external package: `Greeter`.

If your package contains multiple targets that depend on each other you will
need to specify their interdependencies. Here is an example:

```swift
import PackageDescription

let package = Package(
    name: "Example",
    targets: [
        Target(
            name: "top",
            dependencies: [.Target(name: "bottom")]),
        Target(
            name: "bottom")
```

The targets are named how your subdirectories are named.

* * *

## Usage

You use the Swift Package Manager through subcommands of the `swift` command.

### `swift build`

The `swift build` command builds a package and its dependencies.
If you are developing packages, you will use `swift build`

### `swift get`

The `swift get` command downloads packages and any dependencies into a new container.
If you are deploying packages, you will use `swift get`.
