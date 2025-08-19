# Adding dependencies to a Swift package

Use other Swift packages, system libraries, or binary dependencies in your package.

## Overview

To depend on another Swift package, define a dependency and the requirements for its version if it's remote, then add a product of that dependency to one or more of your targets.

A remote dependency requires a location, represented by a URL, and a requirement on the versions the package manager may use.

The following example illustrates a package that depends on [PlayingCard](https://github.com/apple/example-package-playingcard), using `from` to require at least version `4.0.0`, and allow any other version up to the next major version that is available at the time of dependency resolution.
It then uses the product `PlayingCard` as a dependency for the target `MyPackage`:

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(url: "https://github.com/apple/example-package-playingcard.git", 
                 from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: [
                .product(name: "PlayingCard", 
                         package: "example-package-playingcard")
            ]
        ),
        .testTarget(
            name: "MyPackageTests",
            dependencies: ["MyPackage"]
        ),
    ]
)
```

The package manager automatically resolves packages when you invoke <doc:SwiftRun> or <doc:SwiftBuild>. 
You can explicitly resolve the packages with the command <doc:PackageResolve>.
For more information on resolving package versions, see <doc:ResolvingPackageVersions>.

### Constraining dependency versions

Constrain the version of a remote dependency when you declare the dependency.
The package manager uses git tags, each interpreted as a semantic version, to identify eligible versions of packages.

> Note: tags for package versions should include all three components of a semantic version: major, minor, and patch. 
> Tags that only include one or two of those components are not interpreted as semantic versions.

Use the version requirement when you declare the dependency to limit what the package manager can choose.
The version requirement can be a range of possible semantic versions, a specific semantic version, a branch name, or a commit hash.
The API reference documentation for [Package.Dependency](https://developer.apple.com/documentation/packagedescription/package/dependency) defines the methods to use.   

### Packages with Traits

Traits, introduced with Swift 6.1, allow packages to offer additional API that may include optional dependencies.
Packages offer traits to provide expanded API beyond the core of a package.
For example, a package may provide experimental API, optional API that requires additional dependencies, or otherwise default functionality that a developer may want to disable in specific circumstances.
If a package offers traits, using that package as a dependency without any declared traits uses the default traits defined by the package.
In the following example dependency declaration, the package uses the default set of traits from the dependency, if any are defined:
```swift
dependencies: [
  .package(url: "https://github.com/swiftlang/example-package-playingcard", 
           from: "4.0.0")
]
```

To determine what traits a package offers, including its defaults, inspect its `Package.swift` manifest.

Adding a trait should only expand the API offered by a package.
If a package offers default traits, you can choose to not use those traits by declaring an empty set of traits when you declare the dependency.
The following example dependency declaration uses the dependency with no traits, even if the package normally provides a set of default traits to enable:

```swift
dependencies: [
  .package(url: "https://github.com/swiftlang/example-package-playingcard", 
           from: "4.0.0",
           traits: [])
]
```

> Note: By disabling any default traits, you may be removing available APIs from the dependency you use. 

To learn how to provide packages with traits, see <doc:PackageTraits>.

### Local Dependencies

To use a local package as a dependency, use either [package(name:path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(name:path:)) or [package(path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(path:)) to define it with the local path to the package.
Local dependencies do not enforce version constraints, and instead use the version that is available at the path you provide.

### System Library Dependencies

In addition to depending on Swift packages, you can also depend on system libraries or, on Apple platforms, precompiled binary dependencies.

For more information on using a library provided by the system as a dependency, see <doc:AddingSystemLibraryDependency>.

### Precomiled Binary Targets for Apple platforms

To add a dependency on a precompiled binary target, specify a `.binaryTarget` in your list of targets, using either 
[binarytarget(name:url:checksum:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:url:checksum:)) for a downloadable target, 
or [binarytarget(name:path:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:path:)) for a local binary.
After adding the binary target, you can add it to the list of dependencies for any other target. 

For more information on identifying and verifying a binary target, see [Identifying binary dependencies](https://developer.apple.com/documentation/xcode/identifying-binary-dependencies).
For more information on creating a binary target, see [Creating a multiplatform binary framework bundle](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle).

## Topics

- <doc:ResolvingPackageVersions>
- <doc:PackageTraits>
- <doc:ResolvingDependencyFailures>
- <doc:AddingSystemLibraryDependency>
- <doc:ExampleSystemLibraryPkgConfig>
- <doc:EditingDependencyPackage>
