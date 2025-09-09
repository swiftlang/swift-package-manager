//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import PackageModel
import XCTest

class ManifestTests: XCTestCase {
    func testRequiredTargets() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.targetsRequired(for: .everything).map(\.name).sorted(), [
                "Bar",
                "Baz",
                "Foo",
                "FooBar",
                "MyPlugin",
            ])
        }

        do {
            let manifest = Manifest.createLocalSourceControlManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.targetsRequired(for: .specific(["Foo", "Bar"])).map(\.name).sorted(), [
                "Bar",
                "Baz",
                "Foo",
                "MyPlugin",
            ])
        }
    }

    func testRequiredDependencies() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar1", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Bar2", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Bar3", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo1"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo1", dependencies: ["Foo2", "Bar1"]),
            TargetDescription(name: "Foo2", dependencies: [.product(name: "B2", package: "Bar2")]),
            TargetDescription(name: "Foo3", dependencies: ["Bar3"]),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(
                try manifest.dependenciesRequired(for: .everything).map(\.identity.description).sorted(),
                [
                    "bar1",
                    "bar2",
                    "bar3",
                ]
            )
        }

        do {
            let manifest = Manifest.createLocalSourceControlManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(
                try manifest.dependenciesRequired(for: .specific(["Foo"])).map(\.identity.description).sorted(),
                [
                    "bar1", // Foo → Foo1 → Bar1
                    "bar2", // Foo → Foo1 → Foo2 → Bar2
                    "bar3", // Foo → Foo1 → Bar1 → could be from any package due to pre‐5.2 tools version.
                ]
            )
        }

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            XCTAssertEqual(
                try manifest.dependenciesRequired(for: .everything).map(\.identity.description).sorted(),
                [
                    "bar1",
                    "bar2",
                    "bar3",
                ]
            )
        }

        do {
            let manifest = Manifest.createLocalSourceControlManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets
            )

            #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
            XCTAssertEqual(
                manifest.dependenciesRequired(for: .specific(["Foo"]), nil).map(\.identity.description).sorted(),
                [
                    "bar1", // Foo → Foo1 → Bar1
                    "bar2", // Foo → Foo1 → Foo2 → Bar2
                    // (Bar3 is unreachable.)
                ]
            )
            #endif
        }
    }

    func testIsTraitEnabled_WhenNoTraitsInManifest() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: [],
                pruneDependencies: true // Since all dependencies are used, this shouldn't affect the outcome.
            )

            for trait in traits.sorted(by: { $0.name < $1.name }) {
                XCTAssertThrowsError(try manifest.isTraitEnabled(trait, Set(traits.map(\.name)))) { error in
                    XCTAssertEqual("\(error)", """
                    Trait '\(
                        trait
                            .name
                    )' is not declared by package 'foo' (Foo). There are no available traits declared by this package.
                    """)
                }
            }
        }
    }

    func testIsTraitEnabled_WhenInvalidTraitQueried() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: traits,
                pruneDependencies: true // Since all dependencies are used, this shouldn't affect the outcome.
            )

            // Test `isTraitEnabled` when the trait we're querying for does not exist.
            XCTAssertThrowsError(try manifest.isTraitEnabled(.init(stringLiteral: "IDontExist"), ["default"])) { error in
                XCTAssertEqual("\(error)", """
                Trait 'IDontExist' is not declared by package 'foo' (Foo). The available traits declared by this package are: Trait1, Trait2.
                """)
            }

            // Test `isTraitEnabled` when the set of enabled traits contains a trait that isn't defined in the package.
            XCTAssertThrowsError(try manifest.isTraitEnabled(.init(stringLiteral: "Trait1"), ["IDontExist"])) { error in
                XCTAssertEqual("\(error)", """
                Trait 'IDontExist' is not declared by package 'foo' (Foo). The available traits declared by this package are: Trait1, Trait2.
                """)
            }

            // Test `isTraitEnabled` when the set of enabled traits contains a trait that isn't defined in the package, and the queried trait is the same non-existant trait.
            XCTAssertThrowsError(try manifest.isTraitEnabled(.init(stringLiteral: "IDontExist"), ["IDontExist"])) { error in
                XCTAssertEqual("\(error)", """
                Trait 'IDontExist' is not declared by package 'foo' (Foo). The available traits declared by this package are: Trait1, Trait2.
                """)
            }

            // Test `isTraitEnabled` when the set of enabled traits contains a trait that isn't defined in the package, and the queried trait is another non-existant trait.
            XCTAssertThrowsError(try manifest.isTraitEnabled(.init(stringLiteral: "IDontExistPart2"), ["IDontExist"])) { error in
                XCTAssertEqual("\(error)", """
                Trait 'IDontExistPart2' is not declared by package 'foo' (Foo). The available traits declared by this package are: Trait1, Trait2.
                """)
            }

        }
    }

    func testEnabledTraits_WhenTraitsNotSupported() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: [],
                pruneDependencies: true // Since all dependencies are used, this shouldn't affect the outcome.
            )

            // Enabled Traits when passed a TraitConfiguration:

            // When passed .disableAllTraits configuration
            XCTAssertThrowsError(try manifest.enabledTraits(using: .disableAllTraits)) { error in
                XCTAssertEqual("\(error)", """
                    Disabled default traits on package 'foo' (Foo) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.
                    """)
            }

            // When passed .enableAllTraits configuration
            XCTAssertThrowsError(try manifest.enabledTraits(using: .enabledTraits(["Trait1"]))) { error in
                XCTAssertEqual("\(error)", """
                    Traits [Trait1] have been enabled on package 'foo' (Foo) that declares no traits.
                    """)
            }

            XCTAssertNoThrow(try manifest.enabledTraits(using: .enableAllTraits))
            XCTAssertNoThrow(try manifest.enabledTraits(using: .default))

            // Enabled Traits when passed explicitly enabled traits list:

            // If given a parent package, and the enabled traits being passed don't exist:
            XCTAssertThrowsError(try manifest.enabledTraits(using: ["Trait1"], .init(identity: "qux"))) { error in
                XCTAssertEqual("\(error)", """
                    Package 'qux' enables traits [Trait1] on package 'foo' (Foo) that declares no traits.
                    """)
            }

            // If given a parent package, and the default traits are disabled:
            XCTAssertThrowsError(try manifest.enabledTraits(using: [], .init(identity: "qux"))) { error in
                XCTAssertEqual("\(error)", """
                    Disabled default traits by package 'qux' on package 'foo' (Foo) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break.
                    """)
            }
        }
    }

    func testIsTraitEnabled_WhenNoDefaultTraitsAndNoConfig() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Buzz", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar", "Boo"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(
                name: "Bar",
                dependencies: [.product(name: "Baz", package: "Baz", condition: .init(traits: ["Trait2"]))]
            ),
            TargetDescription(name: "Boo", dependencies: [.product(name: "Buzz", package: "Buzz")]),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: traits
            )

            // Assure that the trait-guarded dependencies pruned.
            XCTAssertEqual(
                try manifest.dependenciesRequired(for: .everything).map(\.identity.description).sorted(),
                [
                    "buzz",
                ]
            )

            // Assure that each trait is not enabled.
            for trait in traits {
                XCTAssertEqual(try manifest.isTraitEnabled(trait, ["default"]), false)
            }

            // Now, create a version of the same manifest but with the `pruneDependencies` flag set to true.
            let manifestPrunedDeps = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: traits,
                pruneDependencies: true
            )

            // Since we've enabled pruned dependencies for this manifest, we should only see "buzz"
            XCTAssertEqual(
                try manifestPrunedDeps.dependenciesRequired(for: .everything).map(\.identity.description).sorted(),
                [
                    "buzz",
                ]
            )

            // Assure that each trait is not enabled.
            for trait in traits {
                XCTAssertEqual(try manifestPrunedDeps.isTraitEnabled(trait, ["default"]), false)
            }
        }
    }

    func testIsTraitEnabled_WhenDefaultTraitsAndNoTraitConfig() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets,
                traits: traits
            )

            for trait in traits.sorted(by: { $0.name < $1.name }) {
                XCTAssertTrue(try manifest.isTraitEnabled(trait, Set(traits.map(\.name))))
            }
        }
    }

    func testEnabledTraits_WithAllTraitsDisabled() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3")
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: traits,
                pruneDependencies: true // Since all dependencies are used, this shouldn't affect the outcome.
            )

            XCTAssertNoThrow(try {
                let enabledTraits = try XCTUnwrap(manifest.enabledTraits(using: .disableAllTraits))
                XCTAssertEqual(enabledTraits, [])
            }())
        }
    }

    func testEnabledTraits_WithOnlyDefaultTraitsEnabled() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar"),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets,
                traits: traits
            )

            // Calculate the enabled traits without an explicitly declared set of enabled traits.
            // This should default to fetching the default traits, if they exist (which in this test case
            // they do), and then will calculate the transitive set of traits that are enabled.
            let allEnabledTraits = try XCTUnwrap(manifest.enabledTraits(using: .default)).sorted()
            XCTAssertEqual(allEnabledTraits, ["Trait1", "Trait2"])
        }
    }

    func testEnabledTraits_WithExplicitTraitsEnabled() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar"),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets,
                traits: traits
            )

            // Calculate the enabled traits with an explicitly declared set of enabled traits.
            // This should override the default traits (since it isn't explicitly passed in here).
            let allEnabledTraitsWithoutDefaults = try manifest.enabledTraits(using: .enabledTraits(["Trait3"])).sorted()
            XCTAssertEqual(allEnabledTraitsWithoutDefaults, ["Trait3"])

            // Calculate the enabled traits with an explicitly declared set of enabled traits,
            // including the default traits. Since default traits are explicitly enabled in the
            // passed set of traits, this will be factored into the calculation.
            let allEnabledTraitsWithDefaults = try manifest.enabledTraits(using: .enabledTraits(["default", "Trait3"])).sorted()
            XCTAssertEqual(allEnabledTraitsWithDefaults, ["Trait1", "Trait2", "Trait3"])
        }
    }

    func testEnabledTraits_WithAllTraitsEnabled() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(name: "Foo", dependencies: ["Bar"]),
            TargetDescription(name: "Bar"),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets,
                traits: traits
            )

            // Calculate the enabled traits with all traits enabled flag.
            let allEnabledTraits = try manifest.enabledTraits(using: .enableAllTraits).sorted()
            XCTAssertEqual(allEnabledTraits, ["Trait1", "Trait2", "Trait3"])
        }
    }

    func testTraitGuardedDependencies() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .product(
                        name: "Bar",
                        package: "Bar",
                        condition: .init(traits: ["Trait2"])
                    ),
                    .product(
                        name: "Baz",
                        package: "Baz"
                    ),
                    .product(
                        name: "Bar2",
                        package: "Bar"
                    )
                ]
            ),
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: traits
            )

            let traitGuardedDependencies = manifest.traitGuardedTargetDependencies()

            XCTAssertEqual(
                traitGuardedDependencies,
                [
                    "Bar": [
                        .product(name: "Bar", package: "Bar", condition: .init(traits: ["Trait2"]))
                    ]
                ]
            )
        }
    }

    func testIsTargetDependencyEnabled() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Cosmic", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let unguardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Bar",
            package: "Blah"
        )

        let trait3GuardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Baz",
            package: "Buzz",
            condition: .init(traits: ["Trait3"])
        )

        let defaultTraitGuardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Bam",
            package: "Boom",
            condition: .init(traits: ["Trait2"])
        )

        let enabledTargetDependencyWithSamePackage: TargetDescription.Dependency = .product(
            name: "Kaboom",
            package: "Boom"
        )

        let manyTraitsEnableTargetDependency: TargetDescription.Dependency = .product(
            name: "Supernova",
            package: "Cosmic",
            condition: .init(traits: ["Space", "Music"])
        )

        let target = try TargetDescription(
            name: "Foo",
            dependencies: [
                unguardedTargetDependency,
                trait3GuardedTargetDependency,
                defaultTraitGuardedTargetDependency,
                enabledTargetDependencyWithSamePackage,
                manyTraitsEnableTargetDependency
            ]
        )

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
            TraitDescription(name: "Space"),
            TraitDescription(name: "Music"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: [target],
                traits: traits
            )

            // Test if an unguarded target dependency is enabled; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                unguardedTargetDependency,
                enabledTraits: ["default"]
            ))

            // Test if a trait-guarded dependency is enabled when passed a set of enabled traits that
            // unblock this target dependency; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                trait3GuardedTargetDependency,
                enabledTraits: ["Trait3"]
            ))

            // Test if a trait-guarded dependency is enabled when passed all traits enabled;
            // should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                trait3GuardedTargetDependency,
                enabledTraits: ["Trait1", "Trait2", "Trait3"]
            ))

            // Test if a trait-guarded dependency is enabled when there are no enabled traits passsed.
            XCTAssertFalse(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                trait3GuardedTargetDependency,
                enabledTraits: ["default"]
            ))

            // Test if a target dependency guarded by default traits is enabled when passed no explicitly
            // enabled traits; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                defaultTraitGuardedTargetDependency,
                enabledTraits: ["default"]
            ))

            // Test if a target dependency guarded by default traits is enabled when passed an empty set
            // of enabled traits, overriding the default traits; should be false.
            XCTAssertFalse(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                defaultTraitGuardedTargetDependency,
                enabledTraits: []
            ))

            // Test if a target dependency that isn't guarded by traits wherein it uses a product
            // from the same package as another target dependency that is guarded by traits; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                enabledTargetDependencyWithSamePackage,
                enabledTraits: []
            ))

            // Test variations of traits that enable a target dependency that is unguarded by many traits.
            XCTAssertFalse(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                manyTraitsEnableTargetDependency,
                enabledTraits: []
            ))
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                manyTraitsEnableTargetDependency,
                enabledTraits: ["Space"]
            ))
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                manyTraitsEnableTargetDependency,
                enabledTraits: ["Music"]
            ))
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                manyTraitsEnableTargetDependency,
                enabledTraits: ["Music", "Space"]
            ))
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(
                target: "Foo",
                manyTraitsEnableTargetDependency,
                enabledTraits: ["Trait3", "Music", "Space", "Trait1", "Trait2"]
            ))
        }
    }

    func testIsPackageDependencyUsed() throws {
        let bar: PackageDependency = .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
        let baz: PackageDependency = .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0"))
        let bam: PackageDependency = .localSourceControl(path: "/Bam", requirement: .upToNextMajor(from: "1.0.0"))
        let drinks: PackageDependency = .localSourceControl(path: "/Drinks", requirement: .upToNextMajor(from: "1.0.0"))

        let dependencies: [PackageDependency] = [
            bar,
            baz,
            bam,
            drinks,
        ]

        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let unguardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Bar",
            package: "Bar"
        )

        let trait3GuardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Baz",
            package: "Baz",
            condition: .init(traits: ["Trait3"])
        )

        let defaultTraitGuardedTargetDependency: TargetDescription.Dependency = .product(
            name: "Bam",
            package: "Bam",
            condition: .init(traits: ["Trait2"])
        )

        let unguardedTargetDependencyWithBamPackage: TargetDescription.Dependency = .product(
            name: "Qux",
            package: "Bam"
        )

        let manyTraitsGuardingTargetDependency: TargetDescription.Dependency = .product(
            name: "Coffee",
            package: "Drinks",
            condition: .init(traits: ["Sugar", "Cream"])
        )

        let target = try TargetDescription(
            name: "Foo",
            dependencies: [
                unguardedTargetDependency,
                trait3GuardedTargetDependency,
                defaultTraitGuardedTargetDependency,
                manyTraitsGuardingTargetDependency
            ]
        )

        let targetWithUnguardedBamPackageDep = try TargetDescription(
            name: "Foo",
            dependencies: [
                unguardedTargetDependency,
                trait3GuardedTargetDependency,
                defaultTraitGuardedTargetDependency,
                unguardedTargetDependencyWithBamPackage,
            ]
        )

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3"),
            TraitDescription(name: "Sugar"),
            TraitDescription(name: "Cream"),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: [target],
                traits: traits
            )

            let manifestWithBamDependencyAlwaysUsed = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: [targetWithUnguardedBamPackageDep],
                traits: traits
            )

            XCTAssertTrue(try manifest.isPackageDependencyUsed(bar, enabledTraits: []))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(baz, enabledTraits: ["Trait3"]))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(bam, enabledTraits: []))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(bam, enabledTraits: ["Trait3"]))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(drinks, enabledTraits: []))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(drinks, enabledTraits: ["Sugar"]))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(drinks, enabledTraits: ["Cream"]))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(drinks, enabledTraits: ["Sugar", "Cream"]))

            // Configuration of the manifest that includes a case where there exists a target
            // dependency that depends on the same package as another target dependency, but
            // is unguarded by traits; therefore, this package dependency should be considered used
            // in every scenario, regardless of the passed trait configuration.
            XCTAssertTrue(try manifestWithBamDependencyAlwaysUsed.isPackageDependencyUsed(bam, enabledTraits: []))
            XCTAssertTrue(try manifestWithBamDependencyAlwaysUsed.isPackageDependencyUsed(bam, enabledTraits: ["Trait3"]))
        }
    }

    func testPrunedDependencies_WhenAllDependenciesUsed() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .product(
                        name: "Bar",
                        package: "Bar",
                        condition: .init(traits: ["Trait1"])
                    ),
                ]
            ),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: [.init(name: "default", enabledTraits: ["Trait1"]), "Trait1", "Trait2"],
                // Since all dependencies are used, this shouldn't affect the outcome.
                pruneDependencies: true
            )

            // The list of required dependencies should remain the same, since all depenencies are being
            // used in the current manifest.
            let calculatedDependencies = try manifest.dependenciesRequired(for: .everything)
            XCTAssertEqual(calculatedDependencies.map(\.identity).sorted(), dependencies.map(\.identity).sorted())
        }
    }

    func testPrunedDependencies_WhenSomeDependenciesUsed() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .product(
                        // This dependency on Bar is guarded by Trait1
                        name: "Bar",
                        package: "Bar",
                        condition: .init(traits: ["Trait1"])
                    ),
                ]
            ),
            TargetDescription(
                name: "Bar",
                dependencies: [
                    .product(
                        name: "Baz",
                        package: "Baz",
                        condition: .init(traits: ["Trait2"])
                    ),
                ]
            ),
            TargetDescription(
                name: "Baz",
                dependencies: [
                    "MyPlugin",
                    "Bar", // Bar as a dependency is not trait-guarded here
                ]
            ),
            TargetDescription(name: "FooBar", dependencies: []),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: [.init(name: "default", enabledTraits: ["Trait1"]), "Trait1", "Trait2"],
                pruneDependencies: true
            )

            let calculatedDependenciesWithDefaultTraits = try manifest.dependenciesRequired(for: .everything)
            XCTAssertEqual(
                calculatedDependenciesWithDefaultTraits.map(\.identity).sorted(),
                [
                    PackageIdentity(stringLiteral: "Bar"),
                    PackageIdentity(stringLiteral: "MyPlugin"),
                ]
            )

            let calculatedDependenciesWithTrait2EnabledOnly = try manifest.dependenciesRequired(
                for: .everything,
                ["Trait2"]
            )
            XCTAssertEqual(
                calculatedDependenciesWithTrait2EnabledOnly.map(\.identity).sorted(),
                [
                    PackageIdentity(stringLiteral: "Bar"),
                    PackageIdentity(stringLiteral: "Baz"),
                    PackageIdentity(stringLiteral: "MyPlugin"),
                ]
            )

            let calculatedDependenciesWithAllTraitsEnabled = try manifest.dependenciesRequired(
                for: .everything,
                ["Trait1", "Trait2"]
            )
            XCTAssertEqual(
                calculatedDependenciesWithAllTraitsEnabled.map(\.identity).sorted(),
                [
                    PackageIdentity(stringLiteral: "Bar"),
                    PackageIdentity(stringLiteral: "Baz"),
                    PackageIdentity(stringLiteral: "MyPlugin"),
                ]
            )
        }
    }

    func testDependenciesGuardedByTraits_WithTraitConfigurations() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .product(
                        name: "Bar",
                        package: "Bar",
                        condition: .init(traits: ["Trait1"])
                    ),
                ]
            ),
            TargetDescription(name: "Bar", dependencies: ["Baz"]),
            TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            TargetDescription(name: "FooBar", dependencies: []),
            TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool),
        ]

        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/MyPlugin", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                dependencies: dependencies,
                products: products,
                targets: targets,
                traits: [.init(name: "default", enabledTraits: ["Trait1"]), "Trait1", "Trait2"]
            )

            // With an empty list of enabled traits, the `Bar` dependency should be trait-guarded here.
            let traitGuardedDependencies = manifest.dependenciesTraitGuarded(withEnabledTraits: [])
            XCTAssertEqual(traitGuardedDependencies.map(\.identity), [PackageIdentity(path: "/Bar")])

            // When using default traits (since we omit a list of enabled traits here),
            // `Bar` should not be trait-guarded since `Trait1` is enabled by default.
            let noTraitGuardedDependencies = manifest.dependenciesTraitGuarded(withEnabledTraits: ["default"])
            XCTAssertEqual(noTraitGuardedDependencies, [])
        }
    }

    func testTargetDescriptionDependencyName_ForProduct() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .product(
                        name: "Bar",
                        package: "Blah"
                    ),
                ]
            ),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertTrue(manifest.targets.count == 1)
            let target = try XCTUnwrap(manifest.targets.first)
            XCTAssertEqual(target.name, "Foo")

            for dependency in target.dependencies {
                XCTAssertEqual(dependency.name, "Bar")
            }
        }
    }

    func testTargetDescriptionDependencyName_ForTarget() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    .target(
                        name: "Baz"
                    ),
                ]
            ),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertTrue(manifest.targets.count == 1)
            let target = try XCTUnwrap(manifest.targets.first)
            XCTAssertEqual(target.name, "Foo")

            for dependency in target.dependencies {
                XCTAssertEqual(dependency.name, "Baz")
            }
        }
    }

    func testTargetDescriptionDependencyName_ForByName() throws {
        let products = try [
            ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = try [
            TargetDescription(
                name: "Foo",
                dependencies: [
                    "Boo",
                ]
            ),
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertTrue(manifest.targets.count == 1)
            let target = try XCTUnwrap(manifest.targets.first)
            XCTAssertEqual(target.name, "Foo")

            for dependency in target.dependencies {
                XCTAssertEqual(dependency.name, "Boo")
            }
        }
    }
}
