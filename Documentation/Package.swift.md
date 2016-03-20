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
        .Package(url: "ssh://git@example.com/Greeter.git", versions: Version(1,0,0)..<Version(2,0,0))
    ]
)
```

A `Package.swift` file is a Swift file
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
    ]
)
```

The targets are named how your subdirectories are named.

If you want to exclude some files and folders from Package, you can simple list them in the `exclude`. Every item specifies a relative folder path from the Root folder of the package

```swift
let package = Package(
    name: "Example",
    exclude: ["tools", "docs", "Sources/libA/images"]
)
```

A package can require dependencies that are only needed during develop,
as example for testing purposes. `testDependencies` are only fetched 
when you build current package. They are not fetched if a package is 
specified as a dependency in other package.

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    testDependencies: [
        .Package(url: "ssh://git@example.com/Tester.git", versions: Version(1,0,0)..<Version(2,0,0)),
    ]
)
```

## Customizing Builds

That the manifest is Swift allows for powerful customization, for example:

```swift
import PackageDescription

var package = Package()

#if os(Linux)
let target = Target(name: "LinuxSources/foo")
package.targets.append(target)
#endif
```

With a standard configuration file format like JSON such a feature would result in a dictionary structure with increasing complexity for every such feature.


## Depending on Apple Modules (eg. Foundation)

At this time there is no explicit support for depending on Foundation, AppKit, etc, though importing these modules should work if they are present in the proper system location. We will add explicit support for system dependencies in the future. Note that at this time the Package Manager has no support for iOS, watchOS, or tvOS platforms.
