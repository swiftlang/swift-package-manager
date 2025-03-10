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
                targets: targets,
                traits: []
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

    func testIsTargetDependencyEnabled() throws {
        let dependencies: [PackageDependency] = [
            .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
            .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let unguardedTargetDependency: TargetDescription.Dependency = .product(name: "Bar", package: "Blah")
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

        let target = try TargetDescription(
            name: "Foo",
            dependencies: [
                unguardedTargetDependency,
                trait3GuardedTargetDependency,
                defaultTraitGuardedTargetDependency
            ]
        )

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
                targets: [target],
                traits: traits
            )

            // Test if an unguarded target dependency is enabled; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(target: "Foo", unguardedTargetDependency, enabledTraits: nil))

            // Test if a trait-guarded dependency is enabled when passed a set of enabled traits that
            // unblock this target dependency; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(target: "Foo", trait3GuardedTargetDependency, enabledTraits: ["Trait3"]))

            // Test if a trait-guarded dependency is enabled when passed a flag that enables all traits;
            // should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(target: "Foo", trait3GuardedTargetDependency, enabledTraits: nil, enableAllTraits: true))

            // Test if a trait-guarded dependency is enabled when there are no enabled traits passsed.
            XCTAssertFalse(try manifest.isTargetDependencyEnabled(target: "Foo", trait3GuardedTargetDependency, enabledTraits: nil))

            // Test if a target dependency guarded by default traits is enabled when passed no explicitly
            // enabled traits; should be true.
            XCTAssertTrue(try manifest.isTargetDependencyEnabled(target: "Foo", defaultTraitGuardedTargetDependency, enabledTraits: nil))

            // Test if a target dependency guarded by default traits is enabled when passed an empty set
            // of enabled traits, overriding the default traits; should be false.
            XCTAssertFalse(try manifest.isTargetDependencyEnabled(target: "Foo", defaultTraitGuardedTargetDependency, enabledTraits: []))
        }
    }

    func testIsPackageDependencyUsed() throws {
        let bar: PackageDependency = .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0"))
        let baz: PackageDependency = .localSourceControl(path: "/Baz", requirement: .upToNextMajor(from: "1.0.0"))
        let bam: PackageDependency = .localSourceControl(path: "/Bam", requirement: .upToNextMajor(from: "1.0.0"))

        let dependencies: [PackageDependency] = [
            bar,
            baz,
            bam
        ]

        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let unguardedTargetDependency: TargetDescription.Dependency = .product(name: "Bar", package: "Bar")
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

        let target = try TargetDescription(
            name: "Foo",
            dependencies: [
                unguardedTargetDependency,
                trait3GuardedTargetDependency,
                defaultTraitGuardedTargetDependency
            ]
        )

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
                targets: [target],
                traits: traits
            )

            XCTAssertTrue(try manifest.isPackageDependencyUsed(bar, enabledTraits: nil))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(bar, enabledTraits: []))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(baz, enabledTraits: nil))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(baz, enabledTraits: ["Trait3"]))
            XCTAssertTrue(try manifest.isPackageDependencyUsed(bam, enabledTraits: nil))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(bam, enabledTraits: []))
            XCTAssertFalse(try manifest.isPackageDependencyUsed(bam, enabledTraits: ["Trait3"]))
        }
    }

    func testTargetDescriptionDependencyName_ForProduct() throws {
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(
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
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(
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
        let products = [
            try ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
        ]

        let targets = [
            try TargetDescription(
                name: "Foo",
                dependencies: [
                    "Boo"
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
