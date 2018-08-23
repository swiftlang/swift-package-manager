# PackageDescription API Version 4.2

## Table of Contents

* [Overview](README.md)
* [Usage](Usage.md)
* [PackageDescription API Version 3](PackageDescriptionV3.md)
* [PackageDescription API Version 4](PackageDescriptionV4.md)
* [**PackageDescription API Version 4.2**](PackageDescriptionV4_2.md)
  * [Swift Language Version](#swift-language-version)
  * [Local Dependencies](#local-dependencies)
  * [System Library Targets](#system-library-targets)
* [Resources](Resources.md)

---

The PackageDescription 4.2 contains one breaking and two additive changes to [PackageDescription API Version 4](PackageDescriptionV4.md).

## Swift Language Version

The `swiftLanguageVersions` takes an array of `SwiftVersion` enum:

```swift
public enum SwiftVersion {
    case v3
    case v4
    case v4_2
    case version(String)
}
```

Example usage:

```swift
// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "HTTPClient",
    ...
    swiftLanguageVersions: [.v4, .v4_2]
)
```

## Local Dependencies

Local dependences are packages on disk that can be referred directly using their
paths. Local dependencies are only allowed in the root package and they override
all dependencies with same name in the package graph. Example declaration:

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(path: "../example-package-playingcard"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: ["PlayingCard"]
        ),
    ]
)
```

## System Library Targets

System library targets supply the same metadata needed to adapt system libraries
to work with the package manager, but as a target. This allows packages to embed
these targets with the libraries that need them.

```swift
// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ZLib",
    products: [
        .library(name: "ZLib", targets: ["ZLib"]),
    ],
    targets: [
        .systemLibrary(
            name: "CZLib")
        .target(
            name: "ZLib",
            dependencies: ["CZLib"]),
    ]
)
```
