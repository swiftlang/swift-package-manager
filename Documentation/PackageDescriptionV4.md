# PackageDescription API Version 4

## Table of Contents

* [Overview](README.md)
* [Usage](Usage.md)
* [PackageDescription API Version 3](PackageDescriptionV3.md)
* [**PackageDescription API Version 4**](PackageDescriptionV4.md)
  * [Target Format Reference](#target-format-reference)
  * [Package Manifest File Format Reference](#package-manifest-file-format-reference)
  * [Version](#version)
* [Resources](Resources.md)

---

## Target Format Reference

All targets should be declared in the `Package.swift` manifest file.  Unless the
relative path of the target is declared, the Package Manager will look for
a directory matching the name of the target in these places:

Regular targets: package root, Sources, Source, src, srcs.  
Test targets: Tests, package root, Sources, Source, src, srcs. 

## Package Manifest File Format Reference

### Package

```swift
Package(
    name: String,
    pkgConfig: String? = nil,
    providers: [SystemPackageProvider]? = nil,
    products: [Product] = [],
    dependencies: [Dependency] = [],
    targets: [Target] = [],
    swiftLanguageVersions: [Int]? = nil
)
```

\- [name](#name): The name of the package.  
\- [pkgConfig](#pkgconfig): Name of the pkg-config (.pc) file to get the
additional flags for system modules.  
\- [providers](#providers): Defines hints to display for installing system
modules.  
\- [products](#products): The products vended by the package.  
\- [dependencies](#dependencies): The external package dependencies.  
\- [targets](#targets): The list of targets in the package.  
\- [swiftLanguageVersions](#swiftlanguageversions): Specifies the set of
supported Swift language versions.  

#### name

```swift
import PackageDescription

let package = Package(
    name: "FooBar"
)
```

This is the minimal requirement for a manifest to be valid. However, at least
one target is required to build the package.

#### pkgConfig

This property should only be used for System Module Packages. It defines the
name of the pkg-config (.pc) file that should be searched and read to get the
additional flags like include search path, linker search path, system libraries
to link etc.

```swift
import PackageDescription

let package = Package(
    name: "CGtk3",
    pkgConfig: "gtk+-3.0"
)
```

Here `gtk+-3.0.pc` will be searched in standard locations for the current
system. Users can provide their own paths for location of pc files using the
environment variable, `PKG_CONFIG_PATH`, which will be searched before the
standard locations.

_NOTE: This feature does not require pkg-config to be installed. However, if
installed it will used to find additional platform specific pc file locations
which might be unknown to SwiftPM._

#### providers

This property should only be used for system module packages. It can be used to
provide _hints_ for users to install a System Module using a system package
manager like homebrew, apt-get etc.

_NOTE: SwiftPM will **never** execute the command, and only provide suggestions._

```swift
import PackageDescription

let package = Package(
    name: "CGtk3",
    pkgConfig: "gtk+-3.0",
    providers: [
        .brew(["gtk+3"]),
        .apt(["gtk3"])
    ]
)
```

In this case if SwiftPM determines that GTK 3 package is not installed, it will
output an appropriate hint depending on which platform the user is on i.e.
macOS, Ubuntu, etc.

#### products

This is the list of all the products that are vended by the package. A target is
available to other packages only if it is a part of some product.

Two types of products are supported:

* library: A library product contains library targets. It should contain the
    targets which are supposed to be used by other packages, i.e. the public API
    of a library package. The library product can be declared static, dynamic
    or automatic. It is recommended to use automatic so the Package Manager can
    decide appropriate linkage.

* executable: An executable product is used to vend an executable target. This
    should only be used if the executable needs to be made available to
    other packages.

Example:

```swift
let package = Package(
    name: "Paper",
    products: [
        .executable(name: "tool", targets: ["tool"]),
        .library(name: "Paper", targets: ["Paper"]),
        .library(name: "PaperStatic", type: .static, targets: ["Paper"]),
        .library(name: "PaperDynamic", type: .dynamic, targets: ["Paper"]),
    ],
    dependencies: [
        .package(url: "http://github.com/SwiftyJSON/SwiftyJSON", from: "1.2.3"),
        .package(url: "../CHTTPParser", .upToNextMinor(from: "2.2.0")),
        .package(url: "http://some/other/lib", .exact("1.2.3")),
    ],
    targets: [
        .target(
            name: "tool",
            dependencies: [
                "Paper",
                "SwiftyJSON"
            ]),
        .target(
            name: "Paper",
            dependencies: [
                "Basic",
                .target(name: "Utility"),
                .product(name: "CHTTPParser"),
            ])
    ]
)
```

#### dependencies

This is the list of packages that the package depends on. You can specify
a URL (or local path) to any valid Swift package.

```swift
import PackageDescription

let package = Package(
    name: "Example",
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "1.0.0"),
    ],
    target: [
        .target(name: "Foo", dependencies: ["SwiftyJSON"]),
    ]
)
```

A package dependency represents the location and the required version
information of an external dependency. The version range controls what versions
of a package dependency are expected to work with the current package. When the
package manager is fetching the complete set of packages required to build
a package, it considers all of the version range specifications from all of the
packages in order to select appropriate versions.

The following options are available for declaring a package dependency:

```swift

// 1.0.0 ..< 2.0.0
.package(url: "/SwiftyJSON", from: "1.0.0"),

// 1.2.0 ..< 2.0.0
.package(url: "/SwiftyJSON", from: "1.2.0"),

// 1.5.8 ..< 2.0.0
.package(url: "/SwiftyJSON", from: "1.5.8"),

// 1.5.8 ..< 2.0.0
.package(url: "/SwiftyJSON", .upToNextMajor(from: "1.5.8")),

// 1.5.8 ..< 1.6.0
.package(url: "/SwiftyJSON", .upToNextMinor(from: "1.5.8")),

// 1.5.8
.package(url: "/SwiftyJSON", .exact("1.5.8")),

// Constraint to an arbitrary open range.
.package(url: "/SwiftyJSON", "1.2.3"..<"1.2.6"),

// Constraint to an arbitrary closed range.
.package(url: "/SwiftyJSON", "1.2.3"..."1.2.8"),

// Branch and revision.
.package(url: "/SwiftyJSON", .branch("develop")),
.package(url: "/SwiftyJSON", .revision("e74b07278b926c9ec6f9643455ea00d1ce04a021"))
```

#### targets

The targets property is used to declare the targets in the package.

```swift
import PackageDescription

let package = Package(
    name: "FooBar",
    targets: [
        .target(name: "Foo", dependencies: []),
        .testTarget(name: "Bar", dependencies: ["Foo"]),
    ]
)
```

The above manifest declares two target, `Foo` and `Bar`. `Bar` is a test target
which depends on `Foo`. The Package Manager will automatically search for the
targets inside package in the [predefined search paths](#target-format-reference).

A target dependency can either be another target in the same package or a target
in one of its package dependencies. All target depenencies, internal or
external, must be explicitly declared.

A target can be further customized with these properties:

* path: This property defines the path to the top-level directory containing the
target's sources, relative to the package root. It is not legal for this path to
escape the package root, i.e., values like "../Foo", "/Foo" are invalid. The
default value of this property will be nil, which means the target will be
searched for in the pre-defined paths. The empty string ("") or dot (".")
implies that the target's sources are directly inside the package root.

* exclude: This property can be used to exclude certain files and directories from
being picked up as sources. Exclude paths are relative to the target path. This
property has more precedence than sources property.

* sources: This property defines the source files to be included in the target.
The default value of this property will be nil, which means all valid source
files found in the target's path will be included. This can contain directories
and individual source files. Directories will be searched recursively for valid
source files. Paths specified are relative to the target path.

* publicHeadersPath: This property defines the path to the directory containing
public headers of a C target.  This path is relative to the target path and
default value of this property is include. *Only valid for C family library
targets*.

Note: It is an error if the paths of two targets overlap (unless resolved with
exclude).

#### swiftLanguageVersions

This property is used to specify the set of supported Swift language versions.

The package manager will select the Swift language version that is most close to
(but not exceeding) the major version of the Swift compiler in use.  It is an
error if a package does not support any version compatible with the current
compiler. For e.g. if Swift language version is set to `[3]`, both Swift 3 and
4 compilers will select '3', and if Swift language version is set to `[3, 4]`,
Swift 3 compiler will select '3' and Swift 4 compiler will select '4'.

If a package does not specify any Swift language versions, the language version
to be used will match the major version of the package's [Swift tools
version](Usage.md#swift-tools-version).  For e.g.: A Swift tools version with
a major version of '3' will imply a default Swift language version of '3', and
a Swift tools version with a major version of '4' will imply a default Swift
language version of '4'.

## Version

A struct representing a [semantic version](http://semver.org).

```swift
Version(
	_ major: Int,
	_ minor: Int,
	_ patch: Int,
	prereleaseIdentifiers: [String] = [],
	buildMetadataIdentifier: [String] = []
)
```

\- *major*: The major version, incremented when you make incompatible API
changes.  
\- *minor*: The minor version, incremented when you add functionality in a
backwards-compatible manner.  
\- *patch*: The patch version, incremented when you make backwards-compatible
bug fixes.  
\- *prereleaseIdentifiers*: Used to denote a pre-released version for eg:
alpha, beta, etc.  
\- *buildMetadataIdentifier*: Optional build meta data for eg: timestamp, hash,
etc.  

A `Version` struct can be initialized using a string literal in following
format:

``` "major.minor.patch[-prereleaseIdentifiers][+buildMetadata]" ```

where `prereleaseIdentifiers` and `buildMetadata` are optional.  
_NOTE: prereleaseIdentifiers are separated by dot (.)._
