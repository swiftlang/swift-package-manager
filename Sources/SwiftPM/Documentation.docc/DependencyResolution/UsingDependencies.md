# Using dependencies

## About Dependencies

Modern development is accelerated by the use of external dependencies (for better and worse). This is great for allowing you to get more done in less time, but adding dependencies to a project has an associated coordination cost.

In addition to downloading and building the source code for a dependency, that dependency's own dependencies must be downloaded and built as well, and so on, until the entire dependency graph is satisfied. To complicate matters further, a dependency may specify version requirements, which may have to be reconciled with the version requirements of other modules with the same dependency.

The role of the package manager is to automate the process of downloading and building all of the dependencies for a project, and minimize the coordination costs associated with code reuse.

Dependencies are specified in your `Package.swift` manifest file.

## Adding Dependencies

To depend on a package, define the dependency and the version in the manifest of
your package, and add a product from that package as a dependency, e.g., if
you want to use https://github.com/apple/example-package-playingcard as
a dependency, add the GitHub URL in the dependencies of `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "MyPackage",
    dependencies: [
        .package(url: "https://github.com/apple/example-package-playingcard.git", from: "3.0.4"),
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: [
                .product(name: "PlayingCard", package: "example-package-playingcard"),
            ]
        ),
        .testTarget(
            name: "MyPackageTests",
            dependencies: ["MyPackage"]
        ),
    ]
)
```

Now you should be able to `import PlayingCard` in the `MyPackage` target.

## Dependency "Hell"

“Dependency Hell” is the colloquialism for a situation where the graph of dependencies required by a project cannot be met. The user is then required to solve the scenario, which is usually a difficult task:

1. The conflict may be in unfamiliar dependencies (of dependencies) that the user did not explicitly request.
2. Due to the nature of development it would be rare for two dependency graphs to be the same. Thus the amount of help other users (often even the package authors) can offer is limited. Internet searches will likely prove fruitless.

A good package manager should be designed from the start to minimize the risk of dependency hell, and where this is not possible, to mitigate it and provide tooling so that the user can solve the scenario with a minimum of trouble. The [Package Manager Community Proposal](Design/PackageManagerCommunityProposal.md) contains our thoughts on how we intend to iterate with these hells in mind.

The following are some of the most common “dependency hell” scenarios:

- Inappropriate Versioning - A package may specify an inappropriate version for a release. For example, a version is tagged `1.2.3`, but introduces extensive, breaking API changes that should be reflected by a major version bump to `2.0.0`.

- Incompatible Major Version Requirements - A package may have dependencies with incompatible version requirements for the same package. For example, if `Foo` depends on `Baz` at version `~>1.0` and `Bar` depends on `Baz` at version `~>2.0`, then there is no one version of `Baz` that can satisfy both requirements. This situation often arises when a dependency shared by many packages updates to a new major version, and it takes a long time for all of those packages to update their dependency.

- Incompatible Minor or Update Version Requirements - A package may have dependencies that are specified too strictly, such that version requirements are incompatible for different minor or update versions. For example, if `Foo` depends on `Baz` at version `==2.0.1` and `Bar` depends on `Baz` at version `==2.0.2`, once again, there is no one version of `Baz` that can satisfy both requirements. This is often the result of a regression introduced in a patch release of a dependency, which causes a package to lock that dependency to a particular version.

- Namespace Collision - A package may have two or more dependencies that have the same name. For example, a `Person` package depends on an `Addressable` package that defines a protocol for assigning a mailing address to a person, as well as an `Addressable` package that defines a protocol for speaking formally to another person.

- Broken Software - A package may have a dependency with an outstanding bug that is impacting usability, security, or performance. This may simply be a matter of timeliness on the part of the package maintainers, or a disagreement about their expectations for the package.

- Global State Conflict - A package may have two or more dependencies that presume to have exclusive access to the same global state. For example, one package may not be able to accommodate another package writing to a particular file path while reading from that same file path.

- Package Becomes Unavailable - A package may have a dependency on a package that becomes unavailable. This may be caused by the source URL becoming inaccessible, or maintainers deleting a published version.
