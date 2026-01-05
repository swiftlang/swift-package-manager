
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
The package manager uses git tags, interpreted as a semantic version, to identify eligible versions of packages.

> Note: tags for package versions should include all three components of a semantic version: major, minor, and patch.
> Tags that only include one or two of those components are not interpreted as semantic versions.

Use the version requirement when you declare the dependency to limit what the package manager can choose.
The version requirement can be a range of possible semantic versions, a specific semantic version, a branch name, or a commit hash.
The API reference documentation for [Package.Dependency](https://docs.swift.org/swiftpm/documentation/packagedescription/package/dependency) defines the methods to use.

### Packages with Traits

Traits, introduced with Swift 6.1, allow packages to offer additional API that may include optional dependencies.
Packages should offer traits to provide API beyond the core of a package.
For example, a package may provide an experimental API, an optional API that requires additional dependencies, or functionality that isn't critical that a developer may want to enable only in specific circumstances.

If a package offers traits and you depend on it without defining the traits to use, the package uses its default set of traits.
In the following example, the dependency `example-package-playingcard` uses its default traits, if it offers any:
```swift
dependencies: [
  .package(url: "https://github.com/swiftlang/example-package-playingcard", 
           from: "4.0.0")
]
```

To determine what traits a package offers, including its defaults, either inspect its `Package.swift` manifest or use <doc:PackageShowDependencies> to print out the resolved dependencies and their traits.

Enabling a trait should only expand the API offered by a package.
If a package offers default traits, you can choose to not use those traits by declaring an empty set of traits when you declare the dependency.
The following example dependency declaration uses the dependency with no traits, even if the package normally provides a set of default traits to enable:

```swift
dependencies: [
  .package(url: "https://github.com/swiftlang/example-package-playingcard", 
           from: "4.0.0",
           traits: [])
]
```

Swift package manager determines the traits to enable using the entire graph of dependencies in a project.
The traits enabled for a dependency is the union of all of the traits that for packages that depend upon it.
For example, if you opt out of all traits, but a dependency you use uses the same package with some trait enabled, the package will use the depdendency with the requested traits enabled.

> Note: By disabling any default traits, you may be removing available APIs from the dependency you use. 

To learn how to provide packages with traits, see <doc:PackageTraits>.

### Local Dependencies

To use a local package as a dependency, use either [package(name:path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(name:path:)) or [package(path:)](https://developer.apple.com/documentation/packagedescription/package/dependency/package(path:)) to define it with the local path to the package.
Local dependencies do not enforce version constraints, and instead use the version that is available at the path you provide.

### System Library Dependencies

In addition to depending on Swift packages, you can also depend on system libraries or, on Apple platforms, precompiled binary dependencies.

For more information on using a library provided by the system as a dependency, see <doc:AddingSystemLibraryDependency>.

### Precompiled Binary Targets for Apple platforms

To add a dependency on a precompiled binary target, specify a `.binaryTarget` in your list of targets, using either 
[binarytarget(name:url:checksum:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:url:checksum:)) for a downloadable target, 
or [binarytarget(name:path:)](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:path:)) for a local binary.
After adding the binary target, you can add it to the list of dependencies for any other target.

For more information on identifying and verifying a binary target, see [Identifying binary dependencies](https://developer.apple.com/documentation/xcode/identifying-binary-dependencies).
For more information on creating a binary target, see [Creating a multiplatform binary framework bundle](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle).

---

### Referencing Artifact Bundles from a Swift Package

Swift Package Manager allows packages to depend on prebuilt artifacts that are
distributed as artifact bundles. Artifact bundles may contain either libraries
or executables, depending on the intended use case.

A Swift package references an artifact bundle by declaring a binary target using
`.binaryTarget`. SwiftPM resolves the artifact bundle during dependency
resolution and selects the appropriate artifact based on the target platform
and configuration.

Artifact bundles are currently used in two primary scenarios:

- Providing prebuilt executables, such as tools used by SwiftPM plugins.
- Providing prebuilt binary libraries, such as static or dynamic libraries
  consumed by package targets.

The following sections describe each use case in more detail.

### ArtifactBundleIndex

Swift Package Manager supports binary targets distributed as artifact bundles.
An artifact bundle may include an `ArtifactBundleIndex` file, which describes
the artifacts contained in the bundle and the platforms or variants they support.

The `ArtifactBundleIndex` is required when an artifact bundle contains multiple
artifacts or supports multiple platforms. SwiftPM uses this index to determine
which artifact to select during dependency resolution.

This section describes the use of artifact bundles for **binary library
dependencies**, such as static or dynamic libraries consumed by Swift package
targets.

An artifact bundle that uses an `ArtifactBundleIndex` has the following structure:

```
MyLibrary.artifactbundle/
├── info.json
├── artifactbundleindex.json
└── artifacts/
    ├── x86_64-apple-macos/
    │   └── libMyLibrary.a
    └── aarch64-apple-macos/
        └── libMyLibrary.a
```

The `artifactbundleindex.json` file describes the artifacts in the bundle and
the target triples they support.

```json
{
  "schemaVersion": "1.0",
  "artifacts": {
    "MyLibrary": {
      "type": "library",
      "variants": [
        {
          "path": "artifacts/x86_64-apple-macos/libMyLibrary.a",
          "supportedTriples": ["x86_64-apple-macos"]
        },
        {
          "path": "artifacts/aarch64-apple-macos/libMyLibrary.a",
          "supportedTriples": ["aarch64-apple-macos"]
        }
      ]
    }
  }
}
```
The values in supportedTriples correspond to Swift target triples. SwiftPM
matches these triples against the build target during dependency resolution to
select the appropriate artifact variant.
```
A binary library artifact bundle is referenced from a Swift package using a
binary target declaration:

.binaryTarget(
    name: "MyLibrary",
    url: "https://example.com/MyLibrary.artifactbundle.zip",
    checksum: "…"
)
```

### Artifact Bundles for SwiftPM Tool Invocation

Artifact bundles can also be used to distribute prebuilt executables that are
invoked by Swift Package Manager, such as tools used by SwiftPM plugins.

In this use case, the artifact bundle contains one or more executable artifacts,
and the ArtifactBundleIndex describes the available executable variants.

An example artifact bundle structure for a tool executable is shown below:
```
MyTool.artifactbundle/
├── info.json
├── artifactbundleindex.json
└── artifacts/
    └── x86_64-apple-macos/
        └── my-tool
```
The corresponding artifactbundleindex.json file describes the executable
artifact:
```json
{
  "schemaVersion": "1.0",
  "artifacts": {
    "my-tool": {
      "type": "executable",
      "variants": [
        {
          "path": "artifacts/x86_64-apple-macos/my-tool",
          "supportedTriples": ["x86_64-apple-macos"]
        }
      ]
    }
  }
}
```

When an artifact bundle containing executables is referenced by a SwiftPM
plugin, SwiftPM resolves the artifact bundle and makes the selected executable
available during tool invocation.

This section focuses on artifact bundles as used by SwiftPM itself. Workflows
involving Apple platform application builds with Xcode, including
XCFramework-based distribution, are not covered here.

## Topics

- <doc:ResolvingPackageVersions>
- <doc:PackageTraits>
- <doc:ResolvingDependencyFailures>
- <doc:AddingSystemLibraryDependency>
- <doc:ExampleSystemLibraryPkgConfig>
- <doc:EditingDependencyPackage>
