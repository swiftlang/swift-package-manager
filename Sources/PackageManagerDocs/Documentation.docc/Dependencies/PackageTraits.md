# Providing configurable packages using traits

Define one or more package traits to offer default and configurable features for a package.

## Overview

Swift packages before version 6.1 offer a non-configurable API surface for each version.
Starting with Swift 6.1, packages may offer traits, which express a configurable API surface for a package.

Use traits to enable additional API beyond the core API of the package.
For example, a trait may enable an experimental API, optional extended functionality that requires additional dependencies, or functionality you may want to enable only in specific circumstances.

Traits that you specify when building a package only activate within the package you're building.
If your package wants to use a trait in a dependent package, it needs to encode the traits it needs in its dependencies.

> Note: Don't remove or disable public API when you enable a trait.

Within the package that defines a trait, the trait expresses conditional compilation.
Swift Package Manager exposes enabled traits as conditional blocks (for example, `#if YourTrait`) that you can use to conditionally enable imports or different compilation paths in code.

Trait names are namespaced within the package that hosts them.
A trait name in one package has no impact on any other package.
Trait names must be [valid Swift identifiers](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure#Identifiers) with the addition of the characters of `-` and `+`.
Don't use the trait names `default` or `defaults` (regardless of capitalization).
These values aren't allowed to avoid confusion with the default traits that a package defines.

### Declare traits

Create a trait to define additional functionality, and define it in the [traits](https://docs.swift.org/swiftpm/documentation/packagedescription/package/traits) property of the package manifest.
Use [`.default(enabledTraits:)`](https://docs.swift.org/swiftpm/documentation/packagedescription/trait/default(enabledtraits:)) to provide the set of traits that the package uses by default.
If you don't define a default set of traits to enable, Swift Package Manager enables no traits by default.

The following example illustrates a single trait, `FeatureA`, that is enabled by default:

```swift
// ...
traits: [
    .trait(name: "FeatureA"),
    .default(enabledTraits: ["FeatureA"]),
],
// ...
```

Traits can also represent a set of other traits, which allows you to group features together.
The following example illustrates defining three traits, and an additional trait (`B-and-C`) that enables both traits `FeatureB` and `FeatureC`:

```swift
// ...
traits: [
    .trait(name: "FeatureA"),
    .trait(name: "FeatureB"),
    .trait(name: "FeatureC"),
    .trait(name: "B-and-C", enabledTraits: ["FeatureB", "FeatureC"]),
    .default(enabledTraits: ["FeatureA"]),
],
// ...
```

For the example above, the default trait is `FeatureA`.

> Note: Changing the default set of traits for your package is a major semantic version change if it removes API surface.
> Adding traits isn't a major version change.

Swift Package Manager treats traits as purely additive, and unifies enabled traits across all packages within the build graph.
Design your traits so that they enable additional API (and their dependencies, if needed).

#### Define mutually exclusive traits

The package manifest format doesn't support declaring mutually exclusive traits.
In the rare case that you need to offer mutually exclusive traits, protect that scenario in code:

```swift
#if FeatureA && FeatureC
#error("FeatureA and FeatureC are mutually exclusive")
#endif // FeatureA && FeatureC
```

> Note: Providing mutually exclusive traits can result in compilation errors when a developer enables them.

### Depend on a package with a trait

A package dependency that doesn't specify traits uses the package with its default traits enabled.
To enable specific traits, add them to the `traits` parameter in the package dependency declaration.

The following example shows how to depend on `swift-configuration` with both the `defaults` and `YAML` traits enabled:

```swift
dependencies: [
    .package(
        url: "https://github.com/apple/swift-configuration.git",
        from: "1.0.0",
        traits: [
            .defaults,
            "YAML"
        ]
    ),
]
```

> Tip: When you specify traits for a dependency, you explicitly define which traits to enable.
> The default traits aren't included automatically.
> To use both the default and additional traits, add `.defaults` to the list of traits you specify.

### Use traits in your code

Use the name of a trait for conditional compilation.
Wrap the additional API surface for that trait within a conditional compilation block.
For example, if the trait `FeatureA` is defined and enabled, the compiler sees and compiles the function `additionalAPI()`:

```swift
#if FeatureA
public func additionalAPI() {
  // ...
}
#endif // FeatureA
```

### Use a trait to enable conditional dependencies

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

The following code wraps the import with the trait's conditional compilation, and defines additional API that uses the dependency:

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
#endif // FeatureB
```
