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

import XCTest
import PackageModel
import _InternalTestSupport

class ManifestTests: XCTestCase {
    func testRequiredTargets() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            try ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar", dependencies: ["Baz"]),
            try TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            try TargetDescription(name: "FooBar", dependencies: []),
            try TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool)
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            XCTAssertEqual(manifest.targetsRequired(for: .everything).map({ $0.name }).sorted(), [
                "Bar",
                "Baz",
                "Foo",
                "FooBar",
                "MyPlugin"
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

            XCTAssertEqual(manifest.targetsRequired(for: .specific(["Foo", "Bar"])).map({ $0.name }).sorted(), [
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

        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo1"])
        ]

        let targets = [
            try TargetDescription(name: "Foo1", dependencies: ["Foo2", "Bar1"]),
            try TargetDescription(name: "Foo2", dependencies: [.product(name: "B2", package: "Bar2")]),
            try TargetDescription(name: "Foo3", dependencies: ["Bar3"]),
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

            XCTAssertEqual(try manifest.dependenciesRequired(for: .everything, nil).map({ $0.identity.description }).sorted(), [
                "bar1",
                "bar2",
                "bar3",
            ])
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

            XCTAssertEqual(try manifest.dependenciesRequired(for: .specific(["Foo"]), nil).map({ $0.identity.description }).sorted(), [
                "bar1", // Foo → Foo1 → Bar1
                "bar2", // Foo → Foo1 → Foo2 → Bar2
                "bar3", // Foo → Foo1 → Bar1 → could be from any package due to pre‐5.2 tools version.
            ])
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

            XCTAssertEqual(try manifest.dependenciesRequired(for: .everything, nil).map({ $0.identity.description }).sorted(), [
                "bar1",
                "bar2",
                "bar3",
            ])
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
            XCTAssertEqual(manifest.dependenciesRequired(for: .specific(["Foo"]), nil).map({ $0.identity.description }).sorted(), [
                "bar1", // Foo → Foo1 → Bar1
                "bar2", // Foo → Foo1 → Foo2 → Bar2
                // (Bar3 is unreachable.)
            ])
            #endif
        }
    }

    func testEnabledTraits_WhenNoTraitsInManifest() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            try ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar", dependencies: ["Baz"]),
            try TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            try TargetDescription(name: "FooBar", dependencies: []),
            try TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool)
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2")
        ]

        do {
            let manifest = Manifest.createRootManifest(
                displayName: "Foo",
                path: "/Foo",
                toolsVersion: .v5_2,
                products: products,
                targets: targets
            )

            for trait in traits.sorted(by: { $0.name < $1.name }) {
                XCTAssertThrowsError(try manifest.isTraitEnabled(trait, Set(traits.map(\.name)))) { error in
                    XCTAssertEqual("\(error)", """
Trait '"\(trait.name)"' is not declared by package 'Foo'. There are no available traits defined by this package.
""")
                }
            }
        }
    }

    func testEnabledTraits_WhenNoDefaultTraitsAndNoConfig() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Buzz", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            try ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar", "Boo"])
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar", dependencies: [.product(name: "Baz", package: "Baz", condition: .init(traits: ["Trait2"]))]),
            try TargetDescription(name: "Boo", dependencies: [.product(name: "Buzz", package: "Buzz")])
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2")
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

            // Assure that the guarded dependencies aren't pruned, since we haven't enabled it for this manifest.
            XCTAssertEqual(try manifest.dependenciesRequired(for: .everything, nil).map({ $0.identity.description }).sorted(), [
                "baz",
                "buzz",
            ])

            // Assure that each trait is not enabled.
            for trait in traits {
                XCTAssertEqual(try manifest.isTraitEnabled(trait, nil), false)
            }

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
            XCTAssertEqual(try manifestPrunedDeps.dependenciesRequired(for: .everything, nil).map({ $0.identity.description }).sorted(), [
                "buzz",
            ])

            // Assure that each trait is not enabled.
            for trait in traits {
                XCTAssertEqual(try manifestPrunedDeps.isTraitEnabled(trait, nil), false)
            }
        }

    }

    func testEnabledTraits_WhenDefaultTraitsAndNoTraitConfig() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            try ProductDescription(name: "Bar", type: .library(.automatic), targets: ["Bar"])
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar", dependencies: ["Baz"]),
            try TargetDescription(name: "Baz", dependencies: ["MyPlugin"]),
            try TargetDescription(name: "FooBar", dependencies: []),
            try TargetDescription(name: "MyPlugin", type: .plugin, pluginCapability: .buildTool)
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2")
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

    func testCalculateAllEnabledTraits_WithOnlyDefaultTraitsEnabled() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar")
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3")
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
            let allEnabledTraits = try manifest.enabledTraits(using: nil)?.sorted()
            XCTAssertEqual(allEnabledTraits, ["Trait1", "Trait2"])
        }
    }

    func testCalculateAllEnabledTraits_WithExplicitTraitsEnabled() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar")
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3")
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
            let allEnabledTraitsWithoutDefaults = try manifest.enabledTraits(using: ["Trait3"])?.sorted()
            XCTAssertEqual(allEnabledTraitsWithoutDefaults, ["Trait3"])

            // Calculate the enabled traits with an explicitly declared set of enabled traits,
            // including the default traits. Since default traits are explicitly enabled in the
            // passed set of traits, this will be factored into the calculation.
            let allEnabledTraitsWithDefaults = try manifest.enabledTraits(using: ["default", "Trait3"])?.sorted()
            XCTAssertEqual(allEnabledTraitsWithDefaults, ["Trait1", "Trait2", "Trait3"])

        }
    }

    func testCalculateAllEnabledTraits_WithAllTraitsEnabled() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(name: "Foo", dependencies: ["Bar"]),
            try TargetDescription(name: "Bar")
        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
            TraitDescription(name: "Trait1", enabledTraits: ["Trait2"]),
            TraitDescription(name: "Trait2"),
            TraitDescription(name: "Trait3")
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
            let allEnabledTraits = try manifest.enabledTraits(using: [], enableAllTraits: true)?.sorted()
            XCTAssertEqual(allEnabledTraits, ["Trait1", "Trait2", "Trait3"])
        }
    }

    func testTraitGuardedDependencies() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),

        ]

        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(
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
                    )
                ]
            ),

        ]

        let traits: Set<TraitDescription> = [
            TraitDescription(name: "default", enabledTraits: ["Trait1"]),
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
                traits: traits
            )

            let traitGuardedDependencies = manifest.traitGuardedDependencies()
            XCTAssertEqual(
                traitGuardedDependencies,
                [
                    "Bar": ["Foo": ["Trait2"]]
                ]
            )
        }
    }
}
