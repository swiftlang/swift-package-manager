# Creating a Swift package

Bundle executable or shareable code into a standalone Swift package.

## Overview

<!-- leverage content from https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode -->

Simply put: a package is a git repository with semantically versioned tags,
that contains Swift sources and a `Package.swift` manifest file at its root.

### Creating a Library Package

A library package contains code which other packages can use and depend on. To
get started, create a directory and run `swift package init`:

    $ mkdir MyPackage
    $ cd MyPackage
    $ swift package init # or swift package init --type library
    $ swift build
    $ swift test

This will create the directory structure needed for a library package with a
target and the corresponding test target to write unit tests. A library package
can contain multiple targets as explained in [Target Format
Reference](PackageDescription.md#target).

### Creating an Executable Package

SwiftPM can create native binaries which can be executed from the command line. To
get started:

    $ mkdir MyExecutable
    $ cd MyExecutable
    $ swift package init --type executable
    $ swift build
    $ swift run
    Hello, World!

This creates the directory structure needed for executable targets. Any target
can be turned into a executable target if there is a `main.swift` file present in
its sources. The complete reference for layout is
[here](PackageDescription.md#target).

### Creating a Macro Package

SwiftPM can generate boilerplate for custom macros:

    $ mkdir MyMacro
    $ cd MyMacro
    $ swift package init --type macro
    $ swift build
    $ swift run
    The value 42 was produced by the code "a + b"

This creates a package with a `.macro` type target with its required dependencies
on [swift-syntax](https://github.com/swiftlang/swift-syntax), a library `.target` 
containing the macro's code, and an `.executableTarget` and `.testTarget` for 
running the macro. The sample macro, `StringifyMacro`, is documented in the Swift 
Evolution proposal for [Expression Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0382-expression-macros.md)
and the WWDC [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166) 
video. See further documentation on macros in [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) book.
