# Reference

## Table of Contents

* [Overview](../#README.md)
* [Usage](UsingSwiftPackageManager.md)
* [**Reference**](Reference.md)
** [Module Format Reference](#module-format-reference)
*** [Source Layouts](#source-layouts)
*** [Other Rules](#other-rules)
** [Package Manifest File Format Reference](#package-manifest-file-format-reference)
*** [Customizing Builds](#customizing-builds)
*** [Depending on Apple Modules](#depending-on-apple-modules)
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

Instructions for how to build a package are provided by a manifest file, called `Package.swift`. You can customize this file to declare build targets or dependencies, include or exclude source files, and specify build configurations for the module or individual files.

Here's an example of a `Package.swift` file:

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    dependencies: [
        .Package(url: "ssh://git@example.com/Greeter.git", versions: Version(1,0,0)..<Version(2,0,0)),
    ]
)
```

A `Package.swift` file is a Swift file that declaratively configures a Package using types defined in the `PackageDescription` module. This manifest declares a dependency on an external package: `Greeter`.

If your package contains multiple targets that depend on each other you will need to specify their interdependencies. Here is an example:

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

A package can require dependencies that are only needed during develop, as example for testing purposes. `testDependencies` are only fetched  when you build current package. They are not fetched if a package is specified as a dependency in other package.

```swift
import PackageDescription

let package = Package(
    name: "Hello",
    testDependencies: [
        .Package(url: "ssh://git@example.com/Tester.git", versions: Version(1,0,0)..<Version(2,0,0)),
    ]
)
```

### Customizing Builds

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

### Depending on Apple Modules

At this time there is no explicit support for depending on Foundation, AppKit, etc, though importing these modules should work if they are present in the proper system location. We will add explicit support for system dependencies in the future. Note that at this time the Package Manager has no support for iOS, watchOS, or tvOS platforms.


