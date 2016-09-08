# Reference

## Table of Contents

* [Overview](README.md)
* [Usage](Usage.md)
* [**Reference**](Reference.md)
  * [Module Format Reference](#module-format-reference)
    * [Source Layouts](#source-layouts)
    * [Other Rules](#other-rules)
  * [Package Manifest File Format Reference](#package-manifest-file-format-reference)
    * [Package](#package)
    * [Package Dependency](#package-dependency)
    * [Version](#version)
    * [Customizing Builds](#customizing-builds)
    * [Build Configurations](#build-configurations)
        * [Debug](#debug)
        * [Release](#release)
    * [Depending on Apple Modules](#depending-on-apple-modules)
* [Resources](Resources.md)

---

## Module Format Reference

### Source Layouts

The modules that `swift build` creates are determined from the filesystem layout of your source files.

For example, if you created a directory with the following layout:

    example/
    example/Sources/bar.swift
    example/Sources/baz.swift

Running `swift build` within directory `example` would produce a single library target: `example/.build/debug/example.a`

To create multiple modules create multiple subdirectories:

    example/Sources/foo/foo.swift
    example/Sources/bar/bar.swift

Running `swift build` would produce two library targets:

* `example/.build/debug/foo.a`
* `example/.build/debug/bar.a`

To generate an executable module (instead of a library module) add a `main.swift` file to that module’s subdirectory:

    example/Sources/foo/main.swift
    example/Sources/bar/bar.swift

Running `swift build` would now produce:

* `example/.build/debug/foo`
* `example/.build/debug/bar.a`

Where `foo` is an executable and `bar.a` a static library.

### Other Rules

* Sub directories of directory named `Tests` become test-modules and are executed by `swift test`. `Tests` or any subdirectory can be excluded via Manifest file. The package manager will add an implicit dependency between the test suite and the target it assumes it is trying to test when the sub directory in `Tests` and package *name* are the same.
* Sub directories of a directory named `Sources`, `Source`, `srcs` or `src` become modules.
* It is acceptable to have no `Sources` directory, in which case the root directory is treated as a single module (place your sources there) or sub directories of the root are considered modules. Use this layout convention for simple projects.

---

## Package Manifest File Format Reference

Instructions for how to build a package are provided by the `Package.swift` manifest file. `Package.swift` is a Swift file defining a single `Package` object. The Package is configured via the APIs used to form that object.

### Package

```swift
Package(
    name: String, 
    pkgConfig: String? = nil, 
    providers: [SystemPackageProvider]? = nil, 
    targets: [Target] = [], 
    dependencies: [Dependency] = [], 
    exclude: [String] = []
)
```

\- [name](#name): The name of the package.  
\- [pkgConfig](#pkgconfig): Name of the pkg-config (.pc) file to get the additional flags for system modules.  
\- [providers](#providers): Defines hints to display for installing system modules.  
\- [targets](#targets): Additional information on each target.  
\- [dependencies](#dependencies): Declare dependencies on external packages.  
\- [exclude](#exclude): Exclude files and directories from package sources.  

### name

```swift
import PackageDescription

let package = Package(
    name: "FooBar"
)
```

It is the minimal requirement for a manifest to be valid. When the sources are located directly under `Sources/` directory, there is only one module and the module name is same as the package name.

### targets

Targets property is used when you have more than one module in your package and want to declare a dependency between them.

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    targets: [
        Target(name: "TestSupport"),
        Target(name: "Bar", dependencies: ["Foo"]),
    ]
)
```

Here `Foo` and `Bar` are modules present under `Sources/` directory. `Foo` module will be built before `Bar` module and `Bar` can import `Foo` if `Foo` is a library.

Note: It is also possible to declare target dependencies between a test and regular module.

### dependencies

This is the list of packages that the current package depends on. You can specify a URL (or local path) to any valid Swift package.

```swift
import PackageDescription

let package = Package(
    name: "Example",
    dependencies: [
        .Package(url: "ssh://git@example.com/Greeter.git", versions: Version(1,0,0)..<Version(2,0,0)),
        .Package(url: "../StringExtensions", "1.0.0"),
        .Package(url: "https://github.com/MyAwesomePackage", majorVersion: 1, minor: 4),
    ]
)
```

See [Package Dependency](#package-dependency).

### exclude

Use this property to exclude files and directories from the package sources.

Every item specifies a relative path from the root of the package.

```swift
let package = Package(
    name: "Foo",
    exclude: ["Sources/Fixtures", "Sources/readme.md", "Tests/FooTests/images"]
)
```

This is helpful when you want to place files like resources or fixtures that should not be considered by the convention system
as possible sources.

### pkgConfig

This property should only be used for System Module Packages. It defines the name of the pkg-config (.pc) file
that should be searched and read to get the additional flags like include search path, linker search path, system libraries
to link etc.

```swift
import PackageDescription

let package = Package(
    name: "CGtk3",
    pkgConfig: "gtk+-3.0"
)
```

Here `gtk+-3.0.pc` will be searched in standard locations for the current system. Users can provide their own paths for location of pc files
using the environment variable, `PKG_CONFIG_PATH`, which will be searched before the standard locations.

Note: This feature does not require pkg-config to be installed. However, if installed it will used to find additional platform specific pc file
locations which might be unknown to SwiftPM.

### providers

This property should only be used for system module packages. It can be used to provide _hints_ for other users to install a System Module using
a system package manager like homebrew, apt-get etc.

Note: SwiftPM will *never* execute the command and only suggest the users to run it.

```swift
import PackageDescription

let package = Package(
    name: "CGtk3",
    pkgConfig: "gtk+-3.0",
    providers: [
        .Brew("gtk+3"),
        .Apt("gtk3")
    ]
)
```

In this case if SwiftPM determines that GTK 3 package is not installed, it will output an appropriate hint depending on which platform
the user is on i.e. macOS, Ubuntu, etc.

### Package Dependency

Package Dependency represents location and Version range of an external dependency.

```swift
Dependency.Package(url: String, versions: Range<Version>)
```
\- url: URL or local path to a Package.  
\- versions: A range of [Version](#version).

```swift
Dependency.Package(url: String, versions: ClosedRange<Version>)
```
\- url: URL or local path to a Package.  
\- versions: A closed range of [Version](#version).

```swift
Dependency.Package(url: String, majorVersion: Int)
```
\- url: URL or local path to a Package.  
\- majorVersion: Major version to consider. Latest available minor Version will be considered.


```swift
Dependency.Package(url: String, majorVersion: Int, minor: Int)
```
\- url: URL or local path to a Package.  
\- majorVersion: Major version to consider.  
\- minor: Minor version to consider.

```swift
Dependency.Package(url: String, _ version: Version)
```
\- url: URL or local path to a Package.  
\- version: The specific [Version](#version) to consider.
  
### Version

A struct representing [Semantic Versioning](http://semver.org).

```swift
Version(
	_ major: Int, 
	_ minor: Int, 
	_ patch: Int,
	prereleaseIdentifiers: [String] = [], 
	buildMetadataIdentifier: String? = nil
)
```

\- major: The major version, incremented when you make incompatible API changes.  
\- minor: The minor version, incremented when you add functionality in a backwards-compatible manner.  
\- patch: The patch version, incremented when you make backwards-compatible bug fixes.  
\- prereleaseIdentifiers: Used to denote a pre-released version for eg: alpha, beta, etc.  
\- buildMetadataIdentifier: Optional build meta data for eg: timestamp, hash, etc.

Version can be initialized using a string literal in following format:

``` "major.minor.patch[-prereleaseIdentifiers][+buildMetadata]" ```

prereleaseIdentifiers and buildMetadata are optional.  
Note: prereleaseIdentifiers are separated by dot (.)

### Customizing Builds

That the manifest is Swift allows for powerful customization, for example:

```swift
import PackageDescription

var package = Package(name: "Example")

#if os(Linux)
let target = Target(name: "LinuxSources/foo")
package.targets.append(target)
#endif
```

With a standard configuration file format like JSON such a feature would result in a dictionary structure with increasing complexity for every such feature.

### Build Configurations

SwiftPM allows two build configurations: Debug (default) and Release.

#### Debug

By default, running `swift build` will build in debug configuration. Alternatively, you can also use `swift build -c debug`. The build artifacts are located in directory called `debug` under build folder.  
A Swift target is built with following flags in debug mode:  

* `-Onone`: Compile without any optimization.
* `-g`: Generate debug information.
* `-enable-testing`: Enable Swift compiler's testability feature.

A C language target is build with following flags in debug mode:

* `-O0`: Compile without any optimization.
* `-g`: Generate debug information.

#### Release

To build in release mode, type: `swift build -c release`. The build artifacts are located in directory called `release` under build folder.  
A Swift target is built with following flags in release mode:  

* `-O`: Compile with optimizations.
* `-whole-module-optimization`: Optimize input files (per module) together instead of individually.

A C language target is build with following flags in release mode:

* `-O2`: Compile with optimizations.

### Depending on Apple Modules

At this time there is no explicit support for depending on Foundation, AppKit, etc, though importing these modules should work if they are present in the proper system location. We will add explicit support for system dependencies in the future. Note that at this time the Package Manager has no support for iOS, watchOS, or tvOS platforms.


