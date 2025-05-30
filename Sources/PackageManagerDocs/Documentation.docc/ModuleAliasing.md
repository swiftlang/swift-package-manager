# Module Aliasing

@Metadata {
    @Available("Swift", introduced: "5.7")
}

Create aliased names for modules to avoid collisions between targets in your package or its dependencies.

## Overview

As you add dependencies to your package, a name collision can occur among modules from different packages.
Module names such as `Logging` or `Utils` are common examples.
In order to resolve the collision, package manager, **from Swift 5.7 or later**, provides the parameter `moduleAliases` when defining dependencies for targets.
You define new unique names for the modules that would otherwise conflict, without requiring any source code changes.

Note the following additional requirements:
* A module being aliased needs to be a pure Swift module only: no ObjC/C/C++/Asm are supported due to a likely symbol collision. Similarly, use of `@objc(name)` should be avoided. 
* A module being aliased cannot be a prebuilt binary due to the impact on mangling and serialization, i.e. source-based only.
* A module being aliased should not be passed to a runtime call such as `NSClassFromString(...)` that converts (directly or indirectly) String to a type in a module since such call will fail.
* If a target mapped to a module being aliased contains resources, they should be asset catalogs, localized strings, or resources that do not require explicit module names.
* If a product that a module being aliased belongs to has a conflicting name with another product, at most one of the products can be a non-automatic library type.


### How to Use

Module aliases are defined as a dictionary parameter in a target's dependencies where the key is the original module name in conflict and the value is a user-defined new unique name:

```swift
    targets: [ 
        .target(
            name: "MyTarget",
            dependencies: [ 
                .product(
                    name: "Utils",
                    package: "MyPackage",
                    moduleAliases: ["Utils": "MyUtils"]
                )
            ]
        )
    ]
```

This will rename the `Utils` module in the `MyPackage` package to the new user-defined unique name, in this case `MyUtils`; the name of the binary will be `MyUtils.swiftmodule`. No source or manifest changes are required by the dependency package.

To use the aliased module, your root package needs to reference the the new name, i.e. `import MyUtils`.

Consider the following example to go over how module aliasing can be used in more detail.

#### Example

The following example of a package `App` imports the modules `Utils` and `Logging` from a package `swift-draw`.
It wants to add another package dependency `swift-game` and imports the modules `Utils` and `Game` vended from the package. The `Game` module imports `Logging` from the same package.

```
 App
   |— Module Utils (from package ‘swift-draw’)
   |— Module Logging (from package ‘swift-draw’)
   |— Module Utils (from package ‘swift-game’)
   |— Module Game (from package ‘swift-game’)
        |— Module Logging (from package ‘swift-game’)
```

Package manifest `swift-game`
```
{
    name: "swift-game",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
        .library(name: "Game", targets: ["Game"]),
    ],
    targets: [
        .target(name: "Game", dependencies: ["Logging"]),
        .target(name: "Utils", dependencies: []),
        .target(name: "Logging", dependencies: [])
    ]
}
```

Package manifest `swift-draw`
```
{
    name: "swift-draw",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
        .library(name: "Logging", targets: ["Logging"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: []),
        .target(name: "Logging", dependencies: []),
    ]
}
```

##### Analyzing the conflicts 

###### Utils modules

Both `swift-draw` and `swift-game` vend modules with the same name `Utils`, thus causing a conflict. To resolve the collision, a new parameter `moduleAliases` can now be used to disambiguate them.

Package manifest `App`
```
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Utils",
                         package: "swift-draw"),
                .product(name: "Utils",
                         package: "swift-game",
                         moduleAliases: ["Utils": "GameUtils"]),
            ])
    ]
```

This will rename the `Utils` module in package `swift-game` as `GameUtils`; the name of the binary will be `GameUtils.swiftmodule`.

To use the aliased module, `App` needs to reference the the new name, i.e. `import GameUtils`. Its existing `import Utils` statement will continue to reference the `Utils` module from package `swift-draw`, as expected.

Note that the dependency product names are duplicate, i.e. both have the same name `Utils`, which is by default not allowed.
However, this is allowed when module aliasing is used as long as no multiple files with the same product name are created.
This means they must all be automatic library types, or at most one of them can be a static library, dylib, an executable, or any other type that creates a file or a directory with the product name.

###### Transitive Logging modules

Similar to the prior conflict with `Utils`, both the `swift-draw` and `swift-game` packages contain modules with the same name `Logging`, thus causing a conflict.
Although `App` does not directly import `Logging` from `swift-game`, the conflicting module still needs to be disambiguated.

We can use `moduleAliases` again, as follows.

Package manifest `App`
```
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                // Utils module aliasing:
                .product(name: "Utils",
                         package: "swift-draw"),
                .product(name: "Utils",
                         package: "swift-game",
                         moduleAliases: ["Utils": "GameUtils"]),
                // Logging module aliasing:
                .product(name: "Logging",
                         package: "swift-draw"),
                .product(name: "Game",
                         package: "swift-game",
                         moduleAliases: ["Logging": "GameLogging"]),
            ])
    ]
```

The `Logging` module from `swift-game` is renamed as `GameLogging`, and all the references to `Logging` in source files of `Game` are compiled as `GameLogging`. Similar to before, no source or manifest changes are required by the `swift-game` package. 

If more aliases need to be defined, they can be added with a comma delimiter, per below. 

```
    moduleAliases: ["Utils": "GameUtils", "Logging": "GameLogging"]),
```

### Override Module Aliases

If module alias values defined upstream are conflicting downstream, they can be overridden by chaining; add an entry to the `moduleAliases` parameter downstream using the conflicting alias value as a key and provide a unique value. 
