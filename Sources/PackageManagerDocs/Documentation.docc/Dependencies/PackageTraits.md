# Provide configurable packages using traits.

Define one or more traits to offer default and configurable features for a package.

Prior to Swift 6.1, packages offered a non-configurable API surface for each version.
With Swift 6.1, packages may offer traits, which express a configurable API surface from a package.

Use traits to enable additional API that extends beyond the core of what the package provides.
For example, a trait may enable experimental API, optional extended functionality that requires additional dependencies, or a functionality that isn't critical that a developer may want to disable in specific circumstances.

> Note: Traits should always *enable* additional code, never "remove" or disable API when a trait is enabled.

Within the package, traits express conditional compilation, and may also declare additional dependencies that are enabled when that trait is active.

Traits are identified by their names, which are name-spaced within the package hosting them.
Trait names must start with a [Unicode XID start character](https://unicode.org/reports/tr31/#Figure_Code_Point_Categories_for_Identifier_Parsing) (most letters), a digit, or `_`, with subsequent characters a [Unicode XID continue character](https://unicode.org/reports/tr31/#Figure_Code_Point_Categories_for_Identifier_Parsing) or the characters `-` or `+`.
The trait names `default` and `defaults` (regardless of any capitalization) aren't allowed to avoid confusion with the default traits a package defines.

Enabled traits are exposed as conditional blocks (`#if YourTrait`) that you can use to conditionally enable imports or otherwise block out different compilation paths in code.

## Overview

### Declaring Traits

Create a trait to define a discrete amount of additional functionality, and define them in the [traits](https://docs.swift.org/swiftpm/documentation/packagedescription/package/traits) property of the package manifest.
Use [`.default(enabledTraits:)`](https://docs.swift.org/swiftpm/documentation/packagedescription/trait/default(enabledtraits:)) to provide the set of traits that the package uses as a default.
If you don't define a default set of traits to enable, no traits are enabled by default.

```swift
// ...
traits: [
    .trait(name: "FeatureA"),
    .default(enabledTraits: ["FeatureA"]),
],
// ...
```

Traits may also be used to represent a set of other traits, which allows you to group features together.
The following example illustrates defining three small traits, and an additional trait (`B-and-C`) that enable both traits `FeatureB` and `FeatureC`:

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

> Note: Changing the default set of traits should be considered a major semantic version change, as it can potentially remove API surface. 

#### Mutually Exclusive Traits

The package manifest format doesn't support declaring mutually exclusive traits.
In the rare case that you need to offer mutually exclusive traits, protect that scenario in code:

```swift
#if FeatureA && FeatureC
#error("FeatureA and FeatureC are mutually exclusive")
#endif // FeatureA && FeatureC
```

### Using traits in your code

Use the names of traits for conditional compilation.
Wrap the additional API surface and functionality you offer for specific trait within a conditional compilation block.
For example, if the trait `FeatureA` is defined and enabled, the following conditional compilation is enabled:

```swift
#if FeatureA
public func additionalAPI() {
  // ...
}
#endif // FeatureA
```

### Using a trait to enable conditional dependencies

You can use a trait to optionally include a dependency, or a dependency with specific traits enabled, for the additional functionality that you expose with a trait.
To do so, add the dependency you need to the manifest's `dependencies` declaration.
Then use a conditional dependency that uses the traits defined in the package to add that dependency to a target.

The following example illustrates the relevant portions of a manifest that defines a trait `FeatureB`, a local dependency that defines a trait to enable additional functionality on that dependency, and a conditional flag on the target that uses that dependency for the target when `FeatureB` is enabled:

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

With the above example, the following code illustrates wrapping the import that brings in the dependency with the trait's conditional compilation, and later defines more API that uses that dependency:

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
