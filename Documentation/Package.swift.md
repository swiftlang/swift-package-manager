# `Package.swift` — The Manifest File

Instructions for how to build a package are provided by
a manifest file, called `Package.swift`.
You can customize this file to
declare build targets or dependencies,
include or exclude source files,
and specify build configurations for the module or individual files.

Here's an example of a `Package.swift` file:

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    dependencies: [
        .Package(url: "ssh://git@example.com/Greeter.git", versions: "1.0.0"),
    ]
)
```

A `Package.swift` file a Swift file
that declaratively configures a Package
using types defined in the `PackageDescription` module.
This manifest declares a dependency on an external package: `Greeter`.

If your package contains multiple targets that depend on each other you will
need to specify their interdependencies. Here is an example:

```swift
import PackageDescription

let package = Package(
    name: "Example",
    targets: [
        Target(
            name: "top",
            dependencies: [.Target(name: "bottom")]),
        Target(
            name: "bottom")
```

The targets are named how your subdirectories are named.


## Depending on Apple Modules (eg. Foundation)

At this time you cannot use Foundation, UIKit etc. with the Package Manager. Consider this an opportunity to create the fundamental libraries that the Swift community needs and will need for years to come.
