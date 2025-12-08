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

The sample macro, `StringifyMacro`, is documented in the Swift Evolution proposal for [Expression Macros](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0382-expression-macros.md)
and the WWDC [Write Swift macros](https://developer.apple.com/videos/play/wwdc2023/10166) video.
For further documentation, see macros in [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) book.

### Creating a Package based on a custom template

Swift Package Manager can create packages based on custom templates taht authors distribute as Swift packages.
These templates can be obtained from local directories, Git repositories, or package registries, and provide interactive configuration through command-line arguments.
To create a package from a custom template, use the `swift package init` command with the `--type` option along with a template source:

```bash
# From a package registry
$ swift package init --type MyTemplate --package-id author.template-example

# From a Git repository
$ swift package init --type MyTemplate --url https://github.com/author/template-example

# From a local directory
$ swift package init --type MyTemplate --path /path/to/template
```

The template prompts you for configuration options during initialization:

```bash
$ swift package init --type ServerTemplate --package-id example.server-templates
Building template package...
Build of product 'ServerTemplate' complete! (3.2s)

Add a README.md file with an introduction and tour of the code: [y/N] y

Choose from the following:

• Name: crud
  About: Generate CRUD server with database support
• Name: bare  
  About: Generate a minimal server

Type the name of the option:
crud

Pick a database system for data storage. [sqlite3, postgresql] (default: sqlite3):
postgresql

Building for debugging...
Build of product 'ServerTemplate' complete! (1.1s)
```

Templates support the same versioning options as regular Swift package dependencies:

```bash
# Specific version
$ swift package init --type MyTemplate --package-id author.template --exact 1.2.0

# Version range
$ swift package init --type MyTemplate --package-id author.template --from 1.0.0

# Specific branch
$ swift package init --type MyTemplate --url https://github.com/author/template --branch main

# Specific revision
$ swift package init --type MyTemplate --url https://github.com/author/template --revision abc123
```

You can provide template arguments directly to skip interactive prompts:

```bash
$ swift package init --type ServerTemplate --package-id example.server-templates crud --database postgresql --readme true
```

Use the `--build-package` flag to automatically build and validate the generated package:

```bash
$ swift package init --type MyTemplate --package-id author.template --build-package
```

This helps you ensure that your template generates valid, buildable Swift packages.

To learn more about creating and providing templates for Swift packages, read <doc:Templates>.
