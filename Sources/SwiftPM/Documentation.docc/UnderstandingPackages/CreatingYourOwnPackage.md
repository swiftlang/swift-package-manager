# Creating your own package

// FIXME:

A package consists of Swift source files, including the `Package.swift` manifest file. The manifest file, or package manifest, defines the package's name and its contents using the PackageDescription module. A package has one or more targets. Each target specifies a product and may declare one or more dependencies.

A package is a git repository with semantically versioned tags, that contains Swift sources and a `Package.swift` manifest file at its root.

## About Modules

Swift organizes code into _modules_. Each module specifies a namespace and enforces access controls on which parts of that code can be used outside of that module.

A program may have all of its code in a single module, or it may import other modules as _dependencies_. Aside from the handful of system-provided modules, such as Darwin on OS X or GLibc on Linux, most dependencies require code to be downloaded and built in order to be used.

Extracting code that solves a particular problem into a separate module allows for that code to be reused in other situations. For example, a module that provides functionality for making network requests could be shared between a photo sharing app and a program that displays the weather forecast. And if a new module comes along that does a better job, it can be swapped in easily, with minimal change. By embracing modularity, you can focus on the interesting aspects of the problem at hand, rather than getting bogged down solving problems you encounter along the way.

As a rule of thumb: more modules is probably better than fewer modules. The package manager is designed to make creating both packages and apps with multiple modules as easy as possible.

### Building Swift Modules

The Swift Package Manager and its build system needs to understand how to compile your source code. To do this, it uses a convention-based approach which uses the organization of your source code in the file system to determine what you mean, but allows you to fully override and customize these details. A simple example could be:

    foo/Package.swift
    foo/Sources/main.swift

> `Package.swift` is the manifest file that contains metadata about your package. `Package.swift` is documented in a later section.

If you then run the following command in the directory `foo`:

```sh
swift build
```

Swift will build a single executable called `foo`.

To the package manager, everything is a package, hence `Package.swift`. However, this does not mean you have to release your software to the wider world; you can develop your app without ever publishing it in a place where others can see or use it. On the other hand, if one day you decide that your project _should_ be available to a wider audience your sources are already in a form ready to be published. The package manager is also independent of specific forms of distribution, so you can use it to share code within your personal projects, within your workgroup, team or company, or with the world.

Of course, the package manager is used to build itself, so its own source files are laid out following these conventions as well.


## Products

A target may build either a library or an executable as its product. A library contains a module that can be imported by other Swift code. An executable is a program that can be run by the operating system.


## Creating a Library Package

A library package contains code which other packages can use and depend on. To
get started, create a directory and run `swift package init`:

```console
$ mkdir MyPackage
$ cd MyPackage
$ swift package init # or swift package init --type library
$ swift build
$ swift test
```

This will create the directory structure needed for a library package with a
target and the corresponding test target to write unit tests. A library package
can contain multiple targets as explained in [Target Format
Reference](PackageDescription.md#target).

## Creating an Executable Package

SwiftPM can create native binaries which can be executed from the command line. To
get started:

```console
$ mkdir MyExecutable
$ cd MyExecutable
$ swift package init --type executable
$ swift build
$ swift run
Hello, World!
```

This creates the directory structure needed for executable targets. Any target
can be turned into a executable target if there is a `main.swift` file present in
its sources. The complete reference for layout is
[here](PackageDescription.md#target).

## Creating a Macro Package

SwiftPM can generate boilerplate for custom macros:

```console
$ mkdir MyMacro
$ cd MyMacro
$ swift package init --type macro
$ swift build
$ swift run
The value 42 was produced by the code "a + b"
```

This creates a package with a `.macro` type target with its required dependencies
on [swift-syntax](https://github.com/swiftlang/swift-syntax), a library `.target`
containing the macro's code, and an `.executableTarget` and `.testTarget` for
running the macro. The sample macro, `StringifyMacro`, is documented in the Swift
Evolution proposal for [Expression Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0382-expression-macros.md)
and the WWDC [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166)
video. See further documentation on macros in [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) book.

## Creating C Language Targets

C language targets are similar to Swift targets, except that the C language
libraries should contain a directory named `include` to hold the public headers.

To allow a Swift target to import a C language target, add a [target](PackageDescription.md#target) in the manifest file. Swift Package Manager will
automatically generate a modulemap for each C language library target for these
3 cases:

* If `include/Foo/Foo.h` exists and `Foo` is the only directory under the
  include directory, and the include directory contains no header files, then
  `include/Foo/Foo.h` becomes the umbrella header.

* If `include/Foo.h` exists and `include` contains no other subdirectory, then
  `include/Foo.h` becomes the umbrella header.

* Otherwise, the `include` directory becomes an umbrella directory, which means
  that all headers under it will be included in the module.

In case of complicated `include` layouts or headers that are not compatible with
modules, a custom `module.modulemap` can be provided in the `include` directory.

For executable targets, only one valid C language main file is allowed, e.g., it
is invalid to have `main.c` and `main.cpp` in the same target.


## Publishing a Package

To publish a package, create and push a semantic version tag:

    $ git init
    $ git add .
    $ git remote add origin [github-URL]
    $ git commit -m "Initial Commit"
    $ git tag 1.0.0
    $ git push origin master --tags

Now other packages can depend on version 1.0.0 of this package using the github
url.
An example of a published package can be found here:
https://github.com/apple/example-package-fisheryates
