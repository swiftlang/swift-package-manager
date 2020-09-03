# Package

`class Package`

The `Package` type is used to configure the name, products, targets,
dependencies and various other parts of the package.

By convention, the properties of a `Package` are defined in a single nested
initializer statement, and not modified after initialization. For example:

```swift
// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "MyLibrary",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"]),
    ],
    dependencies: [
        .package(url: "https://url/of/another/package/named/Utility", from: "1.0.0"),
    ],
    targets: [
        .target(name: "MyLibrary", dependencies: ["Utility"]),
        .testTarget(name: "MyLibraryTests", dependencies: ["MyLibrary"]),
    ]
)
```

## Methods

<pre>
Package(
    name: String,
    platforms: [<a href="#supportedplatform">SupportedPlatform</a>]? = nil,
    products: [<a href="#product">Product</a>] = [],
    dependencies: [<a href="#package-dependency">Package.Dependency</a>] = [],
    targets: [<a href="#target">Target</a>] = [],
    swiftLanguageVersions: [<a href="#SwiftVersion">SwiftVersion</a>]? = nil,
    cLanguageStandard: <a href="#CLanguageStandard">CLanguageStandard</a>? = nil,
    cxxLanguageStandard: <a href="#CXXLanguageStandard">CXXLanguageStandard</a>? = nil
)
</pre>

### About the Swift Tools Version

A Package.swift manifest file must begin with the string `//
swift-tools-version:` followed by a version number specifier.

Examples:

    // swift-tools-version:3.0.2
    // swift-tools-version:3.1
    // swift-tools-version:4.0
    // swift-tools-version:5.0

The Swift tools version declares the version of the `PackageDescription`
library, the minimum version of the Swift tools and Swift language
compatibility version to process the manifest, and the minimum version of the
Swift tools that are needed to use the Swift package. Each version of Swift
can introduce updates to the `PackageDescription` library, but the previous
API version will continue to be available to packages which declare a prior
tools version. This behavior lets you take advantage of new releases of
Swift, the Swift tools, and the `PackageDescription` library, without having
to update your package's manifest or losing access to existing packages.

# SupportedPlatform

`struct SupportedPlatform`

Represents a platform supported by the package.

By default, the Swift Package Manager assigns a predefined minimum deployment
version for each supported platform unless configured using the `platforms`
API. This predefined deployment version will be the oldest deployment target
version supported by the installed SDK for a given platform. One exception
to this rule is macOS, for which the minimum deployment target version will
start from 10.10. Packages can choose to configure the minimum deployment
target version for a platform by using the APIs defined in this struct. The
Swift Package Manager will emit appropriate errors when an invalid value is
provided for supported platforms, for example, an empty array, multiple declarations
for the same platform, or an invalid version specification.

The Swift Package Manager will emit an error if a dependency is not
compatible with the top-level package's deployment version; the deployment
target of dependencies must be lower than or equal to top-level package's
deployment target version for a particular platform.

## Methods

```swift
/// Configure the minimum deployment target version for the macOS platform.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter version: The minimum deployment target that the package supports.
static func macOS(_ version: SupportedPlatform.MacOSVersion) -> SupportedPlatform

/// Configure the minimum deployment target version for the macOS platform
/// using a custom version string.
///
/// The version string must be a series of 2 or 3 dot-separated integers, for
/// example "10.10" or "10.10.1".
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter versionString: The minimum deployment target as a string representation of 2 or 3 dot-separated integers, e.g. "10.10.1".
static func macOS(_ versionString: String) -> SupportedPlatform

/// Configure the minimum deployment target version for the iOS platform.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter version: The minimum deployment target that the package supports.
static func iOS(_ version: SupportedPlatform.IOSVersion) -> SupportedPlatform

/// Configure the minimum deployment target version for the iOS platform
/// using a custom version string.
///
/// The version string must be a series of 2 or 3 dot-separated integers, for
/// example "8.0" or "8.0.1".
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter versionString: The minimum deployment target as a string representation of 2 or 3 dot-separated integers, e.g. "8.0.1".
static func iOS(_ versionString: String) -> SupportedPlatform

/// Configure the minimum deployment target version for the tvOS platform.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter version: The minimum deployment target that the package supports.
static func tvOS(_ version: SupportedPlatform.TVOSVersion) -> SupportedPlatform

/// Configure the minimum deployment target version for the tvOS platform
/// using a custom version string.
///
/// The version string must be a series of 2 or 3 dot-separated integers, for
/// example "9.0" or "9.0.1".
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter versionString: The minimum deployment target as a string representation of 2 or 3 dot-separated integers, e.g. "9.0.1".
static func tvOS(_ versionString: String) -> SupportedPlatform

/// Configure the minimum deployment target version for the watchOS platform.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter version: The minimum deployment target that the package supports.
static func watchOS(_ version: SupportedPlatform.WatchOSVersion) -> SupportedPlatform

/// Configure the minimum deployment target version for the watchOS platform
/// using a custom version string.
///
/// The version string must be a series of 2 or 3 dot-separated integers, for
/// example "2.0" or "2.0.1".
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameter versionString: The minimum deployment target as a string representation of 2 or 3 dot-separated integers, e.g. "3.0.1".
static func watchOS(_ versionString: String) -> SupportedPlatform
```

# Product

`class Product`

Defines a package product.

A package product defines an externally visible build artifact that is
available to clients of a package. The product is assembled from the build
artifacts of one or more of the package's targets.

A package product can be one of two types:

1. Library

    A library product is used to vend library targets containing the public
    APIs that will be available to clients.

2. Executable

    An executable product is used to vend an executable target. This should
    only be used if the executable needs to be made available to clients.

The following example shows a package manifest for a library called "Paper"
that defines multiple products:

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
        .package(url: "http://example.com.com/ExamplePackage/ExamplePackage", from: "1.2.3"),
        .package(url: "http://some/other/lib", .exact("1.2.3")),
    ],
    targets: [
        .target(
            name: "tool",
            dependencies: [
                "Paper",
                "ExamplePackage"
            ]),
        .target(
            name: "Paper",
            dependencies: [
                "TSCBasic",
                .target(name: "Utility"),
                .product(name: "AnotherExamplePackage"),
            ])
    ]
)
```

## Methods

```swift
/// Create a library product that can be used by clients that depend on this package.
///
/// A library's product can either be statically or dynamically linked. It
/// is recommended to not declare the type of library explicitly to let the
/// Swift Package Manager choose between static or dynamic linking depending
/// on the consumer of the package.
///
/// - Parameters:
///     - name: The name of the library product.
///     - type: The optional type of the library that is used to determine how to link to the library.
///         Leave this parameter unspecified to let to let the Swift Package Manager choose between static or dynamic linking (recommended).
///         If you do not support both linkage types, use `.static` or `.dynamic` for this parameter.
///     - targets: The targets that are bundled into a library product.
public static func library(
    name: String,
    type: Product.Library.LibraryType? = nil,
    targets: [String]
) -> Product

/// Create an executable product.
///
/// - Parameters:
///     - name: The name of the executable product.
///     - targets: The targets that are bundled into an executable product.
public static func executable(name: String, targets: [String]) -> Product
```

# Package Dependency

`class Package.Dependency`

A package dependency consists of a Git URL to the source of the package,
and a requirement for the version of the package that can be used.

The Swift Package Manager performs a process called dependency resolution to
figure out the exact version of the package dependencies that can be used in
your package. The results of the dependency resolution are recorded in the
`Package.resolved` file which will be placed in the top-level directory of
your package.

## Methods

```swift
/// Add a package dependency that is required from the given minimum version,
/// going up to the next major version.
///
/// This is the recommend way to specify a remote package dependency because
/// it allows you to specify the minimum version you require and gives
/// explicit opt-in for new major versions, but otherwise provides maximal
/// flexibility on which version is used. This helps to prevent conflicts in
/// your package dependency graph.
///
/// For example, specifying
///
///    .package(url: "https://example.com/example-package.git", from: "1.2.3"),
///
/// will allow the Swift package manager to select a version like a "1.2.3",
/// "1.2.4" or "1.3.0" but not "2.0.0".
///
/// - Parameters:
///     - url: The valid Git URL of the package.
///     - version: The minimum version requirement.
public static func package(url: String, from version: Version) -> Package.Dependency

/// Add a remote package dependency given a version requirement.
///
/// - Parameters:
///     - url: The valid Git URL of the package.
///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
public static func package(url: String, _ requirement: Package.Dependency.Requirement) -> Package.Dependency

///
/// For example
///
///     .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),
///
/// will allow the Swift package manager to pick versions 1.2.3, 1.2.4, 1.2.5, but not 1.2.6.
///
/// - Parameters:
///     - url: The valid Git URL of the package.
///     - range: The custom version range requirement.
public static func package(url: String, _ range: Range<Version>) -> Package.Dependency

/// Add a package dependency starting with a specific minimum version, going
/// up to and including a specific maximum version.
///
/// For example
///
///     .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),
///
/// will allow the Swift package manager to pick versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
///
/// - Parameters:
///     - url: The valid Git URL of the package.
///     - range: The closed version range requirement.
public static func package(url: String, _ range: ClosedRange<Version>) -> Package.Dependency

/// Add a dependency to a local package on the filesystem.
///
/// The package dependency is used as-is and no source control access is
/// performed. Local package dependencies are especially useful during
/// development of a new package or when working on multiple tightly-coupled
/// packages.
///
/// - Parameter path: The path of the package.
public static func package(path: String) -> Package.Dependency
```

# Package Dependency Requirement

`enum Package.Dependency.Requirement`

The dependency requirement can be defined as one of three different version requirements:

1. Version-based Requirement

    A requirement which restricts what version of a dependency your
    package can use based on its available versions. When a new package
    version is published, it should increment the major version component
    if it has backwards-incompatible changes. It should increment the
    minor version component if it adds new functionality in
    a backwards-compatible manner. And it should increment the patch
    version if it makes backwards-compatible bugfixes. To learn more about
    semantic versioning syntax, see [Version](#version) or visit
    https://semver.org (https://semver.org/).

2. Branch-based Requirement

    Specify the name of a branch that a dependency will follow. This is
    useful when developing multiple packages which are closely related,
    allowing you to keep them in sync during development. Note that
    packages which use branch-based dependency requirements cannot be
    depended-upon by packages which use version-based dependency
    requirements; you should remove branch-based dependency requirements
    before publishing a version of your package.

3. Commit-based Requirement

    A requirement that restricts a dependency to a specific commit
    hash. This is useful if you want to pin your package to a specific
    commit hash of a dependency. Note that packages which use
    commit-based dependency requirements cannot be depended-upon by
    packages which use version-based dependency requirements; you
    should remove commit-based dependency requirements before
    publishing a version of your package.

## Methods

```swift
/// Returns a requirement for the given exact version.
///
/// Specifying exact version requirements are usually not recommended, as
/// they can cause conflicts in your package dependency graph when a package
/// is depended on by multiple other packages.
///
/// Example:
///
///   .exact("1.2.3")
///
/// - Parameters:
///      - version: The exact version to be specified.
public static func exact(_ version: Version) -> Package.Dependency.Requirement

/// Returns a requirement for a source control revision. This is usually
/// specified with the hash of a commit.
///
/// Note that packages which use commit-based dependency requirements
/// cannot be depended-upon by packages which use version-based dependency
/// requirements; you should remove commit-based dependency requirements
/// before publishing a version of your package.
///
/// Example:
///
///   .revision("e74b07278b926c9ec6f9643455ea00d1ce04a021")
///
/// - Parameters:
///     - ref: The Git revision, usually a hash of the commit.
public static func revision(_ ref: String) -> Package.Dependency.Requirement

/// Returns a requirement for a source control branch.
///
/// Note that packages which use branch-based dependency requirements
/// cannot be depended-upon by packages which use version-based dependency
/// requirements; you should remove branch-based dependency requirements
/// before publishing a version of your package.
///
/// Example:
///
///    .branch("develop")
///
/// - Parameters:
///     - name: The name of the branch.
public static func branch(_ name: String) -> Package.Dependency.Requirement

/// Returns a requirement for a version range, starting at the given minimum
/// version and going up to the next major version.
///
/// - Parameters:
///     - version: The minimum version for the version range.
public static func upToNextMajor(from version: Version) -> Package.Dependency.Requirement

/// Returns a requirement for a version range, starting at the given minimum
/// version and going up to the next minor version.
///
/// - Parameters:
///     - version: The minimum version for the version range.
public static func upToNextMinor(from version: Version) -> Package.Dependency.Requirement
```

# Version

`struct Version`

A struct representing a Semantic Version.

Semantic versioning is a specification that proposes a set of rules and
requirements that dictate how version numbers are assigned and incremented.
To learn more about the semantic versioning specification, visit
www.semver.org.

## Semantic Versioning (SemVer) 2.0.0

### The Major Version

The major version signifies breaking changes to the API which requires
updating existing clients. For example, renaming an existing type, removing
a method or changing a method’s signature are considered breaking changes.
This also includes any backwards incompatible bugfixes or behavior changes
of existing API.

### The Minor Version

Increment the minor version if functionality is added in a backward compatible
manner. For example, adding a new method or type without otherwise changing an
API is considered backward-compatible.

### The Patch Version

Increase the patch version if you are making a backward-compatible bugfix.
This allows clients to benefit from bugfixes to your package without
incurring any maintenance burden.

# Target

`class Target`

Targets are the basic building blocks of a package.

Each target contains a set of source files that are compiled into a module or
test suite. Targets can be vended to other packages by defining products that
include them.

Targets may depend on targets within the same package and on products vended
by its package dependencies.

## Methods

```swift
/// Create a library or executable target.
///
/// A target can either contain Swift or C-family source files. You cannot
/// mix Swift and C-family source files within a target. A target is
/// considered to be an executable target if there is a `main.swift`,
/// `main.m`, `main.c` or `main.cpp` file in the target's directory. All
/// other targets are considered to be library targets.
///
/// - Parameters:
///   - name: The name of the target.
///   - dependencies: The dependencies of the target. These can either be other targets in the package or products from package dependencies.
///   - path: The custom path for the target. By default, targets will be looked up in the <package-root>/Sources/<target-name> directory.
///       Do not escape the package root, i.e. values like "../Foo" or "/Foo" are invalid.
///   - exclude: A list of paths to exclude from being considered source files. This path is relative to the target's directory.
///   - sources: An explicit list of source files.
///   - publicHeadersPath: The directory containing public headers of a C-family family library target.
///   - cSettings: The C settings for this target.
///   - cxxSettings: The C++ settings for this target.
///   - swiftSettings: The Swift settings for this target.
///   - linkerSettings: The linker settings for this target.
public static func target(
    name: String,
    dependencies: [Target.Dependency] = [],
    path: String? = nil,
    exclude: [String] = [],
    sources: [String]? = nil,
    publicHeadersPath: String? = nil,
    cSettings: [CSetting]? = nil,
    cxxSettings: [CXXSetting]? = nil,
    swiftSettings: [SwiftSetting]? = nil,
    linkerSettings: [LinkerSetting]? = nil
) -> Target

/// Create a test target.
///
/// Test targets are written using the XCTest testing framework. Test targets
/// generally declare target dependency on the targets they test.
///
/// - Parameters:
///   - name: The name of the target.
///   - dependencies: The dependencies of the target. These can either be other targets in the package or products from other packages.
///   - path: The custom path for the target. By default, targets will be looked up in the <package-root>/Tests/<target-name> directory.
///       Do not escape the package root, i.e. values like "../Foo" or "/Foo" are invalid.
///   - exclude: A list of paths to exclude from being considered source files. This path is relative to the target's directory.
///   - sources: An explicit list of source files.
///   - cSettings: The C settings for this target.
///   - cxxSettings: The C++ settings for this target.
///   - swiftSettings: The Swift settings for this target.
///   - linkerSettings: The linker settings for this target.
public static func testTarget(
    name: String,
    dependencies: [Target.Dependency] = [],
    path: String? = nil,
    exclude: [String] = [],
    sources: [String]? = nil,
    cSettings: [CSetting]? = nil,
    cxxSettings: [CXXSetting]? = nil,
    swiftSettings: [SwiftSetting]? = nil,
    linkerSettings: [LinkerSetting]? = nil
) -> Target

/// Create a system library target.
///
/// System library targets are used to adapt a library installed on the system to
/// work with Swift packages. Such libraries are generally installed by system
/// package managers (such as Homebrew and APT) and exposed to Swift packages by
/// providing a modulemap file along with other metadata such as the library's
/// pkg-config name.
///
/// - Parameters:
///   - name: The name of the target.
///   - path: The custom path for the target. By default, targets will be looked up in the <package-root>/Sources/<target-name> directory.
///       Do not escape the package root, i.e. values like "../Foo" or "/Foo" are invalid.
///   - pkgConfig: The name of the pkg-config file for this system library.
///   - providers: The providers for this system library.
public static func systemLibrary(
    name: String,
    path: String? = nil,
    pkgConfig: String? = nil,
    providers: [SystemPackageProvider]? = nil
) -> Target
```

# Target Dependency

`class Target.Dependency`

Represents dependency on other targets in the package or products from other packages.

## Methods

```swift
/// A dependency on a target in the same package.
public static func target(name: String) -> Target.Dependency

/// A dependency on a product from a package dependency.
public static func product(name: String, package: String) -> Target.Dependency

// A by-name dependency that resolves to either a target or a product,
// as above, after the package graph has been loaded.
public static func byName(name: String) -> Target.Dependency
```

# CSetting
`struct CSetting`

A C-language build setting.

## Methods

```swift
/// Provide a header search path relative to the target's directory.
///
/// Use this setting to add a search path for headers within your target.
/// Absolute paths are disallowed and this setting can't be used to provide
/// headers that are visible to other targets.
///
/// The path must be a directory inside the package.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - path: The path of the directory that should be searched for headers. The path is relative to the target's directory.
///   - condition: A condition which will restrict when the build setting applies.
public static func headerSearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> CSetting

/// Defines a value for a macro. If no value is specified, the macro value will
/// be defined as 1.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - name: The name of the macro.
///   - value: The value of the macro.
///   - condition: A condition which will restrict when the build setting applies.
public static func define(_ name: String, to value: String? = nil, _ condition: BuildSettingCondition? = nil) -> CSetting

/// Set unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
///
/// As the usage of the word "unsafe" implies, the Swift Package Manager
/// can't safely determine if the build flags will have any negative
/// side-effect to the build since certain flags can change the behavior of
/// how a build is performed.
///
/// As some build flags could be exploited for unsupported or malicious
/// behavior, the use of unsafe flags make the products containing this
/// target ineligible to be used by other packages.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - flags: The flags to set.
///   - condition: A condition which will restrict when the build setting applies.
public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> CSetting
```

# CXXSetting

`struct CXXSetting`

A CXX-language build setting.

## Methods

```swift
/// Provide a header search path relative to the target's root directory.
///
/// Use this setting to add a search path for headers within your target.
/// Absolute paths are disallowed and this setting can't be used to provide
/// headers that are visible to other targets.
///
/// The path must be a directory inside the package.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - path: The path of the directory that should be searched for headers. The path is relative to the target's directory.
///   - condition: A condition which will restrict when the build setting applies.
public static func headerSearchPath(_ path: String, _ condition: BuildSettingCondition? = nil) -> CXXSetting

/// Defines a value for a macro. If no value is specified, the macro value will
/// be defined as 1.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - name: The name of the macro.
///   - value: The value of the macro.
///   - condition: A condition which will restrict when the build setting applies.
public static func define(_ name: String, to value: String? = nil, _ condition: BuildSettingCondition? = nil) -> CXXSetting

/// Set unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
///
/// As the usage of the word "unsafe" implies, the Swift Package Manager
/// can't safely determine if the build flags will have any negative
/// side-effect to the build since certain flags can change the behavior of
/// how a build is performed.
///
/// As some build flags could be exploited for unsupported or malicious
/// behavior, the use of unsafe flags make the products containing this
/// target ineligible to be used by other packages.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - flags: The flags to set.
///   - condition: A condition which will restrict when the build setting applies.
public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> CXXSetting
```

# SwiftSetting

`struct SwiftSetting`

A Swift language build setting.

## Methods

```swift
/// Define a compilation condition.
///
/// Compilation conditons are used inside to conditionally compile
/// statements. For example, the Swift compiler will only compile the
/// statements inside the `#if` block when `ENABLE_SOMETHING` is defined:
///
///    #if ENABLE_SOMETHING
///       ...
///    #endif
///
/// Unlike macros in C/C++, compilation conditions don't have an
/// associated value.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - name: The name of the macro.
///   - condition: A condition which will restrict when the build setting applies.
public static func define(_ name: String, _ condition: BuildSettingCondition? = nil) -> SwiftSetting

/// Set unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
///
/// As the usage of the word "unsafe" implies, the Swift Package Manager
/// can't safely determine if the build flags will have any negative
/// side-effect to the build since certain flags can change the behavior of
/// how a build is performed.
///
/// As some build flags could be exploited for unsupported or malicious
/// behavior, the use of unsafe flags make the products containing this
/// target ineligible to be used by other packages.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - flags: The flags to set.
///   - condition: A condition which will restrict when the build setting applies.
public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> SwiftSetting
```

# LinkerSetting

`struct LinkerSetting`

A linker build setting.

## Methods

```swift
/// Declare linkage to a system library.
///
/// This setting is most useful when the library can't be linked
/// automatically (for example, C++ based libraries and non-modular
/// libraries).
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - library: The library name.
///   - condition: A condition which will restrict when the build setting applies.
public static func linkedLibrary(_ library: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting

/// Declare linkage to a system framework.
///
/// This setting is most useful when the framework can't be linked
/// automatically (for example, C++ based frameworks and non-modular
/// frameworks).
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - framework: The framework name.
///   - condition: A condition which will restrict when the build setting applies.
public static func linkedFramework(_ framework: String, _ condition: BuildSettingCondition? = nil) -> LinkerSetting

/// Set unsafe flags to pass arbitrary command-line flags to the corresponding build tool.
///
/// As the usage of the word "unsafe" implies, the Swift Package Manager
/// can't safely determine if the build flags will have any negative
/// side-effect to the build since certain flags can change the behavior of
/// how a build is performed.
///
/// As some build flags could be exploited for unsupported or malicious
/// behavior, the use of unsafe flags make the products containing this
/// target ineligible to be used by other packages.
///
/// - Since: First available in PackageDescription 5.0
///
/// - Parameters:
///   - flags: The flags to set.
///   - condition: A condition which will restrict when the build setting applies.
public static func unsafeFlags(_ flags: [String], _ condition: BuildSettingCondition? = nil) -> LinkerSetting
```

# SwiftVersion

`enum SwiftVersion`

Represents the version of the Swift language that should be used for compiling
Swift sources in the package.

```swift
public enum SwiftVersion {

    @available(_PackageDescription, introduced: 4, obsoleted: 5)
    case v3

    @available(_PackageDescription, introduced: 4)
    case v4

    @available(_PackageDescription, introduced: 4)
    case v4_2

    @available(_PackageDescription, introduced: 5)
    case v5

    /// User-defined value of Swift version.
    ///
    /// The value is passed as-is to Swift compiler's `-swift-version` flag.
    case version(String)
}
```

# CLanguageStandard

`enum CLanguageStandard`

Supported C language standards.

```swift
public enum CLanguageStandard {
    case c89
    case c90
    case iso9899_1990
    case iso9899_199409
    case gnu89
    case gnu90
    case c99
    case iso9899_1999
    case gnu99
    case c11
    case iso9899_2011
    case gnu11
}
```
# CXXLanguageStandard

`enum CXXLanguageStandard`

Supported C++ language standards.

```swift
public enum CXXLanguageStandard {
    case cxx98 = "c++98"
    case cxx03 = "c++03"
    case gnucxx98 = "gnu++98"
    case gnucxx03 = "gnu++03"
    case cxx11 = "c++11"
    case gnucxx11 = "gnu++11"
    case cxx14 = "c++14"
    case gnucxx14 = "gnu++14"
    case cxx1z = "c++1z"
    case gnucxx1z = "gnu++1z"
}
```
