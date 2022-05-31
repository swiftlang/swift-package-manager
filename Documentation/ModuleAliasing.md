# Module Aliasing by SwiftPM

## Overview

The number of package dependencies often grows, with that, a name collision can occur among modules from different packages. Module names such as `Logging` or `Utils` are common examples. In order to resolve the collision, SwiftPM (in 5.7+) introduces a new parameter `moduleAliases`, which allows a user to define new unique names for the conflicting modules without requiring any source code changes.  

## How to Use

Consider the following scenario. `App` imports a module called `Game` from package `swift-game`, and a module called `Utils` from package `swift-draw`. 

```
App
  |— Module Game (from package ‘swift-game’)
  |— Module Utils (from package ‘swift-draw’)
```

The `App` package manifest has the following product dependencies.

```
 targets: [
  .executableTarget(
    name: "App",
    dependencies: [
     .product(name: "Game", package: "swift-game"),
     .product(name: "Utils", package: "swift-draw"),
   ])
 ]
```

There's no collision so far, so everything builds fine. Now `App` updates the version of the `swift-game` package to the latest, and in that version, the package contains a module called `Utils` as one of target dependencies for `Game`. This conflicts with module `Utils` from package `swift-draw`.

```
App
  |— Module Game (from package ‘swift-game’)
      |— Module Utils (from package ‘swift-game’)
  |— Module Utils (from package ‘swift-draw’)
```

To resolve the collision, we can now use a new parameter `moduleAliases` as follows.

```
 targets: [
  .executableTarget(
    name: "App",
    dependencies: [
     .product(name: "Game",
              package: "swift-game",
              moduleAliases: ["Utils": "GameUtils"]),
     .product(name: "Utils",
              package: "swift-draw"),
   ])
 ]
```

This will rename the `Utils` module in packgae `swift-game` to be a new user-provided name `GameUtils` and compile all the source references to `Utils` as `GameUtils` in targets of the product in the package. The name of the binary for the `Utils` module will be `GameUtils.swiftmodule`. No source changes are required by the `swift-game` package. 

If `App` wants to import the `Utils` module from `swift-game`, it needs to directly reference the aliased module in its source code, e.g. `import GameUtils`. If it already contains `import Utils`, it will continue to refer to the `Utils` module from package `swift-draw`, as expected.

If there are more aliases to be defined, they can be added with a comma delimiter, per below. 

```
     .product(name: "Game",
              package: "swift-game",
              moduleAliases: ["Utils": "GameUtils", "Logging": "GameLogging"]),
```

## Override Module Aliases

The `moduleAliases` defined in a downstream package will override the `moduleAliases` values defined in an upstream package. This may be useful if the upstream aliases themselves result in a conflict. 

To illustrate, the `swift-game` package is modified to have the following package dependency. 

```
{
 name: "swift-game",
 dependencies: [
  .package(url: https://.../swift-utils.git),
 ],
 products: [
   .library(name: "Game", targets: ["Game"]),
 ],
 targets: [
   .target(name: "Game",
           dependencies: [
                .product(name: "UtilsProduct",
                         package: "swift-utils",
                         moduleAliases: ["Utils": "SwiftUtils"]),
           ])
 ]
}
```

The module aliases defined in the `App` manifest will override, thus the `Utils` module in `swift-utils` will be renamed `GameUtils` instead of `SwiftUtils`.


## Requirements

* Swift 5.7 and above
* Only pure Swift modules are supported for aliasing: no ObjC/C/C++/Asm due to potential symbol collision. Similarly, `@objc(name)` is discouraged. 
* Source-based only: aliasing prebuilt binaries is not possible due to the impact on mangling and serialization.
* Runtime: direct or indirect calls to convert String to a type in module, e.g. `NSClassFromString(...)`, will fail and should be avoided.
* Resources: only asset catalogs and localized strings are allowed.
