# Provide configurable packages using traits.

Define one or more package traits to offer default and configurable features for a package.

## Overview

Swift packages prior to Swift 6.1 offered a non-configurable API surface for each version.
Starting with Swift 6.1, packages may offer traits, which express a configurable API surface for a package.

Use traits to enable additional API beyond the core API of the package.
For example, a trait may enable an experimental API, optional extended functionality that requires additional dependencies, or functionality that isn't critical that a developer may want to enable only in specific circumstances.

When Swift Package Manager builds with a requested trait, it does so across the package dependency tree, propogating that request for traits throughout the dependencies.
Traits are not confined to targets within a package, instead have a potential effect on all targets being built in the package as well as any dependencies.

> Note: Traits should never "remove" or disable public API when a trait is enabled.

Within the package, traits express conditional compilation, and may be used to declare additional dependencies that are enabled when that trait is active.
Enabled traits are exposed as conditional blocks (for example, `#if YourTrait`) that you can use to conditionally enable imports or different compilation paths in code.

Traits are identified by their names, which are name-spaced within the package that hosts them.
Trait names must be [valid swift identifiers](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure#Identifiers) with the addition of the characters of `-` and `+`.
The trait names `default` and `defaults` (regardless of any capitalization) aren't allowed to avoid confusion with the default traits that a package defines.

### Declaring Traits

Create a trait to define a discrete amount of additional functionality, and define it in the [traits](https://docs.swift.org/swiftpm/documentation/packagedescription/package/traits) property of the package manifest.
Use [`.default(enabledTraits:)`](https://docs.swift.org/swiftpm/documentation/packagedescription/trait/default(enabledtraits:)) to provide the set of traits that the package uses as a default.
If you don't define a default set of traits to enable, no traits are enabled by default.

The following example illustrates a single trait, `FeatureA`, that is enabled by default:

```swift
// ...
traits: [
    .trait(name: "FeatureA"),
    .default(enabledTraits: ["FeatureA"]),
],
// ...
```

Traits may also be used to represent a set of other traits, which allows you to group features together.
The following example illustrates defining three traits, and an additional trait (`B-and-C`) that enables both traits `FeatureB` and `FeatureC`:

```swift
// ...
traits: [
    .trait(name: "FeatureA"),
    .trait(name: "FeatureB"),
    .trait(name: "FeatureC"),
    .trait(name: "B-and-C", enabledTraits: ["FeatureB", "FeatureC"]).
    .default(enabledTraits: ["FeatureA"]),
],
// ...
```

The traits enabled by default for the example above is `FeatureA`.

> Note: Changing the default set of traits for your package is a major semantic version change if it removes API surface.
> Adding additional traits is not a major version change.

Swift Package Manager expects traits to be a purely additive effect while building.
Design your traits such that they enable additional API (and their dependencies, if needed). 

#### Defininig mutually exclusive traits

The package manifest format doesn't support declaring mutually exclusive traits.
In the rare case that you need to offer mutually exclusive traits, protect that scenario in code:

```swift
#if FeatureA && FeatureC
#error("FeatureA and FeatureC are mutually exclusive")
#endif // FeatureA && FeatureC
```

> Note: Providing mutually exclusive traits can result in compilation errors when a developer enables the mutually exclusive traits.

### Using traits in your code

Use the name of a trait for conditional compilation.
Wrap the additional API surface for that trait within a conditional compilation block.
For example, if the trait `FeatureA` is defined and enabled, the compiler see and compile the function `additionalAPI()`:

```swift
#if FeatureA
public func additionalAPI() {
  // ...
}
#endif // FeatureA
```

### Using a trait to enable conditional dependencies

You can use a trait to optionally include a dependency, or a dependency with specific traits enabled, to support the functionality you expose with a trait.
To do so, add the dependency you need to the manifest's `dependencies` declaration,
then use a conditional dependency for a trait or traits defined in the package to add that dependency to a target.

The following example illustrates the relevant portions of a package manifest that defines a trait `FeatureB`, a local dependency that is used only when the trait is enabled:

```swift
// ...
traits: [
    "FeatureB" 
    // this trait exists only within *this* package
],
dependencies: [
    .package( 
        path: "../some/local/path",
        traits: ["DependencyFeatureTrait"] 
    // this enables the trait DependencyFeatureTrait on 
    // the local dependency at ../some/local/path.
    )
]
// ... 
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(
                name: "MyAPI",
                package: "MyDependency",
                condition: .when(traits: ["FeatureB"]) 
    // if the FeatureB trait is enabled in *this* package, then
    // the `MyAPI` product is included as a dependency for `MyTarget`.
            )
        ]
    ),
]
```

With the above example, the following code illustrates wrapping the import with the trait's conditional compilation, and later defines more API that uses the dependency:

```swift
#if FeatureB
    import MyAPI
#endif // FeatureB

// ...

#if FeatureB
    public func additionalAPI() {
        MyAPI.provideExtraFunctionality()
        // ...
    }
#endif // MyTrait
```
