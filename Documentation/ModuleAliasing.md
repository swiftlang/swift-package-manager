# Module Aliasing by SwiftPM

## Overview

The number of package dependencies often grows, with that, a name collision can occur among modules from different packages. Module names such as `Logging` or `Utils` are common examples. In order to resolve the collision, SwiftPM (in 5.7+) introduces a new parameter `moduleAliases`, which allows a user to define new unique names for the conflicting modules without requiring any source code changes.  

## How to Use

Let's consider the following scenarios to go over how module aliasing can be used. 

### Example 1

`App` imports a module called `Utils` from a package `swift-draw`. It wants to add another package dependency `swift-game` and imports a module `Utils` vended from the package.

```
 App
   |— Module Utils (from package ‘swift-draw’)
   |— Module Utils (from package ‘swift-game’)
```

Package manifest `swift-game`
```
{
    name: "swift-game",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: [])
    ]
}
```

Package manifest `swift-draw`
```
{
    name: "swift-draw",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: [])
    ]
}
```

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

The value for the `moduleAliases` parameter is a dictionary where the key is the original module name in conflict and the value is a user-defined new unique name, in this case `GameUtils`. This will rename the `Utils` module in package `swift-game` as `GameUtils`; the name of the binary will be `GameUtils.swiftmodule`. No source or manifest changes are required by the `swift-game` package. 

To use the aliased module, `App` needs to reference the the new name, i.e. `import GameUtils`. Its existing `import Utils` statement will continue to reference the `Utils` module from package `swift-draw`, as expected.

Note that the dependency product names are duplicate, i.e. both have the same name `Utils`, which is by default not allowed. However, this is allowed when module aliasing is used as long as no multiple files with the same product name are created. This means they must all be automatic library types, or at most one of them can be a static library, dylib, an executable, or any other type that creates a file or a directory with the product name. 

### Example 2

`App` imports a module `Utils` from a package `swift-draw`. It wants to add another package dependency `swift-game` and imports a module `Game` vended from the package. The `Game` module imports `Utils` from the same package.

```
App
  |— Module Utils (from package ‘swift-draw’)
  |— Module Game (from package ‘swift-game’)
       |— Module Utils (from package ‘swift-game’)
```

Package manifest `swift-game`
```
{
    name: "swift-game",
    products: [
        .library(name: "Game", targets: ["Game"]),
    ],
    targets: [
        .target(name: "Game", dependencies: ["Utils"])
        .target(name: "Utils", dependencies: [])
    ]
}
```

Similar to Example 1, both packages contain modules with the same name `Utils`, thus causing a conflict. Although `App` does not directly import `Utils` from `swift-game`, the conflicting module still needs to be disambiguated.

We can use `moduleAliases` again, as follows.

Package manifest `App`
```
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Utils",
                         package: "swift-draw"),
                .product(name: "Game",
                         package: "swift-game",
                         moduleAliases: ["Utils": "GameUtils"]),
            ])
    ]
```

The `Utils` module from `swift-game` is renamed as `GameUtils`, and all the references to `Utils` in source files of `Game` are compiled as `GameUtils`. Similar to Example 1, no source or manifest changes are required by the `swift-game` package. 

If more aliases need to be defined, they can be added with a comma delimiter, per below. 

```
    moduleAliases: ["Utils": "GameUtils", "Logging": "GameLogging"]),
```

## Override Module Aliases

If module alias values defined upstream are conflicting downstream, they can be overridden by chaining; add an entry to the `moduleAliases` parameter downstream using the conflicting alias value as a key and provide a unique value. 

To illustrate, the `swift-draw` and `swift-game` packages are modified to have the following dependencies and module aliases. 

Package manifest `swift-draw`
```
{
    name: "swift-draw",
    dependencies: [
        .package(url: https://.../a-utils.git),
        .package(url: https://.../b-utils.git),
    ],
    products: [
        .library(name: "Draw", targets: ["Draw"]),
    ],
    targets: [
               .target(name: "Draw",
                       dependencies: [
                            .product(name: "Utils",
                                     package: "a-utils",
                                     moduleAliases: ["Utils": "FooUtils"]),
                            .product(name: "Utils",
                                     package: "b-utils",
                                     moduleAliases: ["Utils": "BarUtils"]),
               ])
    ]
}
```
Package manifest `swift-game`
```
{
    name: "swift-game",
    dependencies: [
        .package(url: https://.../c-utils.git),
        .package(url: https://.../d-utils.git),
    ],
    products: [
        .library(name: "Game", targets: ["Game"]),
    ],
    targets: [
               .target(name: "Game",
                       dependencies: [
                            .product(name: "Utils",
                                     package: "c-utils",
                                     moduleAliases: ["Utils": "FooUtils"]),
                            .product(name: "Utils",
                                     package: "d-utils",
                                     moduleAliases: ["Utils": "BazUtils"]),
               ])
    ]
}
```

Both packages define `FooUtils` as an alias, thus causing a conflict downstream.
To override it, the `App` manifest can define its own module aliases per below.
```
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Draw",
                         package: "swift-draw",
                         moduleAliases: ["FooUtils": "DrawUtils"]),
                .product(name: "Game",
                         package: "swift-game",
                         moduleAliases: ["FooUtils": "GameUtils"]),
            ])
    ]
```
The `Utils` module from package `a-utils` will be renamed as `DrawUtils`, and `Utils` from package `c-utils` will be renamed as `GameUtils`. Each overridden alias will be applied to all of the targets that depend on each module.

## Requirements

* A package needs to adopt the swift tools version 5.7 and above to use the `moduleAliases` parameter.
* A module being aliased needs to be a pure Swift module only: no ObjC/C/C++/Asm are supported due to a likely symbol collision. Similarly, use of `@objc(name)` should be avoided. 
* A module being aliased cannot be a prebuilt binary due to the impact on mangling and serialization, i.e. source-based only.
* A module being aliased should not be passed to a runtime call such as `NSClassFromString(...)` that converts (directly or indirectly) String to a type in a module since such call will fail.
* If a target mapped to a module being aliased contains resources, they should be asset catalogs, localized strings, or resources that do not require explicit module names.
* If a product that a module being aliased belongs to has a conflicting name with another product, at most one of the products can be a non-automatic library type.
