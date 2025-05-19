# Adding dependencies to a Swift package

Use other swift packages, system libraries, or binary dependencies in your package.

## Overview

To depend on another Swift package, define the dependency and the requirements for its version in your package, then add a product of that package to one or more of your targets.

An external dependency requires a location, represented by a URL, and a requirement on the versions that the package manager may use.
The version requirement can be a commit hash, a branch name, a specific semantic version, or a range of possible semantic versions.
The API reference documentation for [Package.Dependency](https://developer.apple.com/documentation/packagedescription/package/dependency) defines all the methods you can use to specify a dependency.

The following example illustrates a package that depends on [PlayingCard](https://github.com/apple/example-package-playingcard), and uses the product `PlayingCard` as a dependency for the target `MyPackage`:

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(url: "https://github.com/apple/example-package-playingcard.git", from: "3.0.4"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: ["PlayingCard"]
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

### Local Dependencies

To use a local swift package as a dependency, specify either [package(name:path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(name:path:)) or [package(path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(path:)) in the Package manifest, with the local path to the package.

### System Library Dependencies

In addition to depending on Swift packages, you can also depend on system libraries or, on Apple platforms, precompiled binary dependencies.

For more information on using a C library provided by the system as a dependency, see <doc:AddingSystemLibraryDependency>.

### Precomiled Binary Targets for Apple platforms

To add a dependency to a precompiled binary target, specify a `.binaryTarget` in your list of targets, using either 
[binarytarget(name:url:checksum:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:url:checksum:)) for a downloadable target, 
or [binarytarget(name:path:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:path:)) for a local binary.
After adding a binary target, you can add it to the list of dependencies for any other target. 

For more information on identifying and verifying a binary target, see [Identifying binary dependencies](https://developer.apple.com/documentation/xcode/identifying-binary-dependencies).
For more information on creating a binary target, see [Creating a multiplatform binary framework bundle](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle).

## Topics

- <doc:ResolvingPackageVersions>
- <doc:ResolvingDependencyFailures>
- <doc:AddingSystemLibraryDependency>
- <doc:ExampleSystemLibraryPkgConfig>
- <doc:ExampleSystemLibraryWithoutPkgConfig>
