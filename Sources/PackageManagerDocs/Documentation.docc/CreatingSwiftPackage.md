# Creating a Swift package

Bundle executable or shareable code into a standalone Swift package.

## Overview

A Swift package is a directory that contains sources, dependencies, and has a `Package.swift` manifest file at its root.
Swift packages can provide libraries, executables, tests, plugins, and macros.
The package manifest defines what is in the package, which is itself written in Swift.
The [API reference for PackageDescription](https://developer.apple.com/documentation/packagedescription) defines the types, properties, and functions that go into assembling a package manifest.

### Creating a Library Package

Swift package manager supports creating packages using <doc:PackageInit>.
By default, the package manager creates a package structure focused on providing a library.
For example, you can create a directory and run the command `swift package init` to create a package:

```bash
$ mkdir MyPackage
$ cd MyPackage
$ swift package init
```

The structure provided follows package manager conventions, and provides a fully operational example.
In addition to the package manifest, Swift sources are collected by target name under the `Sources` directory, and tests collected, also by target name, under the `Tests` directory:

```
├── Package.swift
├── Sources
│   └── MyPackage
│       └── MyPackage.swift
└── Tests
    └── MyPackageTests
        └── MyPackageTests.swift
```

You can immediately use both of <doc:SwiftBuild> and <doc:SwiftTest>:

```bash
$ swift build
$ swift test
```

### Creating an Executable Package

Swift Package Manager can also create a new package with a simplified structure focused on creating executables.
For example, create a directory and run the `init` command with the option `--type executable` to get a package that provides a "Hello World" executable:

```bash
$ mkdir MyExecutable
$ cd MyExecutable
$ swift package init --type executable
$ swift run
Hello, World!
```

There is an additional option for creating a command-line executable based on the `swift-argument-parser`, convenient for parsing command line arguments and structuring commands.
Use `tool` for the `type` option in <doc:PackageInit>.
Like the `executable` template, it is fully operational and also prints "Hello World".

### Creating a Macro Package

Swift Package Manager can generate boilerplate for custom macros:

```bash
$ mkdir MyMacro
$ cd MyMacro
$ swift package init --type macro
$ swift build
$ swift run
The value 42 was produced by the code "a + b"
```

This creates a package with:

- A `.macro` type target with its required dependencies on [swift-syntax](https://github.com/swiftlang/swift-syntax),
- A library `.target`  containing the macro's code.
- An `.executableTarget` for running the macro.
- A `.testTarget` for test the macro implementation.

> note: A `.testTarget` cannot depend on another `.testTarget`.  To work around this, create a non-test target
  for the test target to depend on.  A runtime error (sample below) will occur if the "test only" target is added as a
  dependency on non-test targets.
>
>    ```
>    dyld[67034]: Library not loaded: @rpath/libTesting.dylib
>    Referenced from: <30F1D85A-75C7-358C-B169-96E34550501C> /Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/swift-package
>    Reason: tried: '/usr/lib/swift/libTesting.dylib' (no such file, not in dyld cache), '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/swift/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/usr/lib/swift/libTesting.dylib' (no such file, not in dyld cache), '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/swift/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file)
>    ```


The sample macro, `StringifyMacro`, is documented in the Swift Evolution proposal for [Expression Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0382-expression-macros.md)
and the WWDC [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166) video.
For further documentation, see macros in [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) book.
