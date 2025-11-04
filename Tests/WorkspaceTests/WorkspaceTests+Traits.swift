//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import PackageModel
import XCTest

extension WorkspaceTests {
    func testTraitConfigurationExists_NoDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    // Trait1 enabled; should be present in list of dependencies
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    // Trait2 disabled; should remove this dependency from graph
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: ["Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Only Trait1 is configured to be enabled; since `pruneDependencies` is false
            // by default, there will be unused dependencies present
            traitConfiguration: .init(enabledTraits: ["Trait1"], enableAllTraits: false)
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "Bar", "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testTraitConfigurationExists_WithDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration overrides default traits; all traits set to enabled.
            traitConfiguration: .init(enabledTraits: [], enableAllTraits: true),
            // With this configuration, no dependencies are unused so nothing should be pruned
            // despite the `pruneDependencies` flag being set to true.
            pruneDependencies: true
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo", "Boo")
                result.check(modules: "Bar", "Baz", "Boo", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Baz", "Boo") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
            result.check(dependency: "boo", at: .checkout(.version("1.0.0")))
        }
    }

    func testTraitConfiguration_WithPrunedDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        // unused dependency due to trait guarding; should be omitted
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                        // unused dependency; should be omitted
                        .sourceControl(path: "./Bam", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration overrides default traits; no traits enabled
            traitConfiguration: .init(enabledTraits: [], enableAllTraits: false),
            pruneDependencies: true
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]

        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Foo")
                result.check(modules: "Bar", "Baz", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: []) }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testNoTraitConfiguration_WithDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"]) // Baz dependency guarded by traits.
                                ),
                                .product(
                                    name: "Boo",
                                    package: "Boo",
                                    condition: .init(traits: ["Trait2"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]), // Baz dependency not guarded by traits.
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Boo", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "Boo",
                    targets: [
                        MockTarget(name: "Boo"),
                    ],
                    products: [
                        MockProduct(name: "Boo", modules: ["Boo"]),
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"])),
            .sourceControl(path: "./Boo", requirement: .exact("1.0.0"), products: .specific(["Boo"])),
        ]
        try await workspace.checkPackageGraph(roots: ["Foo"], deps: deps) { graph, diagnostics in
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Foo")
                result.check(packages: "Baz", "Boo", "Foo")
                result.check(modules: "Bar", "Baz", "Boo", "Foo")
                result.checkTarget("Foo") { result in result.check(dependencies: "Boo") }
                result.checkTarget("Bar") { result in result.check(dependencies: "Baz") }
            }
            XCTAssertNoDiagnostics(diagnostics)
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testInvalidTrait_WhenParentPackageEnablesTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0"), traits: ["TraitNotFound"]),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    traits: ["TraitFound"],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"]), traits: ["TraitFound"]),
        ]

        try await workspace.checkPackageGraphFailure(roots: ["Foo"], deps: deps) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("Trait 'TraitNotFound' enabled by package 'foo' (Foo) is not declared by package 'baz' (Baz). The available traits declared by this package are: TraitFound."), severity: .error)
            }
        }
        await workspace.checkManagedDependencies { result in
            result.check(dependency: "baz", at: .checkout(.version("1.0.0")))
        }
    }

    func testInvalidTraitConfiguration_ForRootPackage() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [
                        MockTarget(
                            name: "Foo",
                            dependencies: [
                                .product(
                                    name: "Baz",
                                    package: "Baz",
                                    condition: .init(traits: ["Trait1"])
                                ),
                            ]
                        ),
                        MockTarget(name: "Bar", dependencies: ["Baz"]),
                    ],
                    products: [
                        MockProduct(name: "Foo", modules: ["Foo", "Bar"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0"), traits: ["TraitFound"]),
                    ],
                    traits: [.init(name: "default", enabledTraits: ["Trait2"]), "Trait1", "Trait2"]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Baz",
                    targets: [
                        MockTarget(name: "Baz"),
                    ],
                    products: [
                        MockProduct(name: "Baz", modules: ["Baz"]),
                    ],
                    traits: ["TraitFound"],
                    versions: ["1.0.0", "1.5.0"]
                ),
            ],
            // Trait configuration containing trait that isn't defined in the root package.
            traitConfiguration: .enabledTraits(["TraitNotFound"]),
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Baz", requirement: .exact("1.0.0"), products: .specific(["Baz"]), traits: ["TraitFound"]),
        ]

        try await workspace.checkPackageGraphFailure(roots: ["Foo"], deps: deps) { diagnostics in
            testDiagnostics(diagnostics) { result in
                result.check(diagnostic: .equal("Trait 'TraitNotFound' enabled by command-line trait configuration is not declared by package 'foo' (Foo). The available traits declared by this package are: Trait1, Trait2, default."), severity: .error)
            }
        }
    }

    func testManyTraitsEnableTargetDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        func createMockWorkspace(_ traitConfiguration: TraitConfiguration) async throws -> MockWorkspace {
            try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    MockPackage(
                        name: "Cereal",
                        targets: [
                            MockTarget(
                                name: "Wheat",
                                dependencies: [
                                    .product(
                                        name: "Icing",
                                        package: "Sugar",
                                        condition: .init(traits: ["BreakfastOfChampions", "DontTellMom"])
                                    ),
                                ]
                            ),
                        ],
                        products: [
                            MockProduct(name: "YummyBreakfast", modules: ["Wheat"])
                        ],
                        dependencies: [
                            .sourceControl(path: "./Sugar", requirement: .upToNextMajor(from: "1.0.0")),
                        ],
                        traits: ["BreakfastOfChampions", "DontTellMom"]
                    ),
                ],
                packages: [
                    MockPackage(
                        name: "Sugar",
                        targets: [
                            MockTarget(name: "Icing"),
                        ],
                        products: [
                            MockProduct(name: "Icing", modules: ["Icing"]),
                        ],
                        versions: ["1.0.0", "1.5.0"]
                    ),
                ],
                traitConfiguration: traitConfiguration
            )
        }


        let deps: [MockDependency] = [
            .sourceControl(path: "./Sugar", requirement: .exact("1.0.0"), products: .specific(["Icing"])),
        ]

        let workspaceOfChampions = try await createMockWorkspace(.enabledTraits(["BreakfastOfChampions"]))
        try await workspaceOfChampions.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "sugar")
                result.check(modules: "Wheat", "Icing")
                result.check(products: "YummyBreakfast", "Icing")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Icing")
                }
            }
        }

        let dontTellMomAboutThisWorkspace = try await createMockWorkspace(.enabledTraits(["DontTellMom"]))
        try await dontTellMomAboutThisWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "sugar")
                result.check(modules: "Wheat", "Icing")
                result.check(products: "YummyBreakfast", "Icing")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Icing")
                }
            }
        }

        let allEnabledTraitsWorkspace = try await createMockWorkspace(.enableAllTraits)
        try await allEnabledTraitsWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "sugar")
                result.check(modules: "Wheat", "Icing")
                result.check(products: "YummyBreakfast", "Icing")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Icing")
                }
            }
        }

        let noSugarForBreakfastWorkspace = try await createMockWorkspace(.disableAllTraits)
        try await noSugarForBreakfastWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal")
                result.check(modules: "Wheat")
                result.check(products: "YummyBreakfast")
            }
        }
    }

    /// Tests that different trait configurations correctly control which conditional dependencies are included.
    /// Verifies that enabling different traits (BreakfastOfChampions vs Healthy) includes different
    /// dependencies, and that both are included with `enableAllTraits` while neither is included with `disableAllTraits`.
    func testTraitsConditionalDependencies() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        func createMockWorkspace(_ traitConfiguration: TraitConfiguration) async throws -> MockWorkspace {
            try await MockWorkspace(
                sandbox: sandbox,
                fileSystem: fs,
                roots: [
                    MockPackage(
                        name: "Cereal",
                        targets: [
                            MockTarget(
                                name: "Wheat",
                                dependencies: [
                                    .product(
                                        name: "Icing",
                                        package: "Sugar",
                                        condition: .init(traits: ["BreakfastOfChampions"])
                                    ),
                                    .product(
                                        name: "Raisin",
                                        package: "Fruit",
                                        condition: .init(traits: ["Healthy"])
                                    )
                                ]
                            ),
                        ],
                        products: [
                            MockProduct(name: "YummyBreakfast", modules: ["Wheat"])
                        ],
                        dependencies: [
                            .sourceControl(path: "./Sugar", requirement: .upToNextMajor(from: "1.0.0")),
                            .sourceControl(path: "./Fruit", requirement: .upToNextMajor(from: "1.0.0")),
                        ],
                        traits: ["Healthy", "BreakfastOfChampions"]
                    ),
                ],
                packages: [
                    MockPackage(
                        name: "Sugar",
                        targets: [
                            MockTarget(name: "Icing"),
                        ],
                        products: [
                            MockProduct(name: "Icing", modules: ["Icing"]),
                        ],
                        versions: ["1.0.0", "1.5.0"]
                    ),
                    MockPackage(
                        name: "Fruit",
                        targets: [
                            MockTarget(name: "Raisin"),
                        ],
                        products: [
                            MockProduct(name: "Raisin", modules: ["Raisin"]),
                        ],
                        versions: ["1.0.0", "1.2.0"]
                    ),
                ],
                traitConfiguration: traitConfiguration
            )
        }


        let deps: [MockDependency] = [
            .sourceControl(path: "./Sugar", requirement: .exact("1.0.0"), products: .specific(["Icing"])),
            .sourceControl(path: "./Fruit", requirement: .exact("1.0.0"), products: .specific(["Raisin"])),
        ]

        let workspaceOfChampions = try await createMockWorkspace(.enabledTraits(["BreakfastOfChampions"]))
        try await workspaceOfChampions.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "sugar")
                result.check(modules: "Wheat", "Icing")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Icing")
                }
            }
        }

        let healthyWorkspace = try await createMockWorkspace(.enabledTraits(["Healthy"]))
        try await healthyWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "fruit")
                result.check(modules: "Wheat", "Raisin")
                result.check(products: "YummyBreakfast", "Raisin")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Raisin")
                }
            }
        }

        let allEnabledTraitsWorkspace = try await createMockWorkspace(.enableAllTraits)
        try await allEnabledTraitsWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal", "sugar", "fruit")
                result.check(modules: "Wheat", "Icing", "Raisin")
                result.check(products: "YummyBreakfast", "Icing", "Raisin")
                result.checkTarget("Wheat") { result in
                    result.check(dependencies: "Icing", "Raisin")
                }
            }
        }

        let boringBreakfastWorkspace = try await createMockWorkspace(.disableAllTraits)
        try await boringBreakfastWorkspace.checkPackageGraph(roots: ["Cereal"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "Cereal")
                result.check(packages: "cereal")
                result.check(modules: "Wheat")
                result.check(products: "YummyBreakfast")
            }
        }
    }

    /// Tests that default traits of a dependency package are automatically enabled when
    ////  the parent doesn't specify traits.
    /// Verifies that the default trait enables its configured traits (Enabled1 and
    /// Enabled2), which in turn enables trait-guarded dependencies in the dependency's package graph.
    func testDefaultTraitsEnabledInPackageDependency() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "RootPackage",
                    targets: [
                        MockTarget(
                            name: "MyTarget",
                            dependencies: [
                                .product(
                                    name: "MyProduct",
                                    package: "PackageWithDefaultTraits",
                                ),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "RootProduct", modules: ["MyTarget"])
                    ],
                    dependencies: [
                        .sourceControl(path: "./PackageWithDefaultTraits", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                ),
            ],
            packages: [
                MockPackage(
                    name: "PackageWithDefaultTraits",
                    targets: [
                        MockTarget(
                            name: "PackageTarget",
                            dependencies: [
                                .product(
                                    name: "GuardedProduct",
                                    package: "GuardedDependency",
                                    condition: .init(traits: ["Enabled1"])
                                )
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "MyProduct", modules: ["PackageTarget"]),
                    ],
                    dependencies: [
                        .sourceControl(path: "./GuardedDependency", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    traits: [
                        "Enabled1",
                        "Enabled2",
                        TraitDescription(name: "default", enabledTraits: ["Enabled1", "Enabled2"]),
                        "NotEnabled"
                    ],
                    versions: ["1.0.0", "1.5.0"]
                ),
                MockPackage(
                    name: "GuardedDependency",
                    targets: [
                        MockTarget(
                            name: "GuardedTarget"
                        )
                    ],
                    products: [
                        MockProduct(name: "GuardedProduct", modules: ["GuardedTarget"])
                    ],
                    versions: ["1.0.0", "1.5.0"]
                )
            ],
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./PackageWithDefaultTraits", requirement: .upToNextMajor(from: "1.0.0")),
        ]

        try await workspace.checkPackageGraph(roots: ["RootPackage"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "RootPackage")
                result.checkPackage("PackageWithDefaultTraits") { package in
                    guard let enabledTraits = package.enabledTraits else {
                        XCTFail("No enabled traits on resolved package \(package.identity.description) that is expected to have enabled traits.")
                        return
                    }

                    let deps = package.dependencies
                    XCTAssertEqual(deps, [PackageIdentity(urlString: "./GuardedDependency")])
                    XCTAssertEqual(enabledTraits, ["Enabled1", "Enabled2"])
                }
            }
        }
    }

    /// Tests the unified trait system where one parent disables default traits with []
    /// while another parent doesn't specify traits (defaults to default traits).
    /// The resulting EnabledTraitsMap should have both disablers AND enabled default traits.
    func testDisablersCoexistWithDefaultTraits() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "RootPackage",
                    targets: [
                        MockTarget(
                            name: "RootTarget",
                            dependencies: [
                                .product(name: "Parent1Product", package: "Parent1"),
                                .product(name: "Parent2Product", package: "Parent2"),
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "RootProduct", modules: ["RootTarget"])
                    ],
                    dependencies: [
                        .sourceControl(path: "./Parent1", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Parent2", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Parent1",
                    targets: [
                        MockTarget(
                            name: "Parent1Target",
                            dependencies: [
                                .product(name: "ChildProduct", package: "ChildPackage")
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Parent1Product", modules: ["Parent1Target"])
                    ],
                    dependencies: [
                        // Parent1 explicitly disables ChildPackage's traits with []
                        .sourceControl(path: "./ChildPackage", requirement: .upToNextMajor(from: "1.0.0"), traits: [])
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Parent2",
                    targets: [
                        MockTarget(
                            name: "Parent2Target",
                            dependencies: [
                                .product(name: "ChildProduct", package: "ChildPackage")
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "Parent2Product", modules: ["Parent2Target"])
                    ],
                    dependencies: [
                        // Parent2 doesn't specify traits, so ChildPackage defaults to default traits
                        .sourceControl(path: "./ChildPackage", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "ChildPackage",
                    targets: [
                        MockTarget(
                            name: "ChildTarget",
                            dependencies: [
                                .product(
                                    name: "GuardedProduct",
                                    package: "GuardedDependency",
                                    condition: .init(traits: ["Feature1"])
                                )
                            ]
                        ),
                    ],
                    products: [
                        MockProduct(name: "ChildProduct", modules: ["ChildTarget"])
                    ],
                    dependencies: [
                        .sourceControl(path: "./GuardedDependency", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    traits: [
                        "Feature1",
                        "Feature2",
                        TraitDescription(name: "default", enabledTraits: ["Feature1"])
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "GuardedDependency",
                    targets: [
                        MockTarget(name: "GuardedTarget")
                    ],
                    products: [
                        MockProduct(name: "GuardedProduct", modules: ["GuardedTarget"])
                    ],
                    versions: ["1.0.0"]
                )
            ]
        )

        let deps: [MockDependency] = [
            .sourceControl(path: "./Parent1", requirement: .exact("1.0.0")),
            .sourceControl(path: "./Parent2", requirement: .exact("1.0.0")),
        ]

        try await workspace.checkPackageGraph(roots: ["RootPackage"], deps: deps) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            PackageGraphTesterXCTest(graph) { result in
                result.check(roots: "RootPackage")
                result.check(packages: "RootPackage", "Parent1", "Parent2", "ChildPackage", "GuardedDependency")

                // Verify ChildPackage has default traits enabled (from Parent2)
                result.checkPackage("ChildPackage") { package in
                    guard let enabledTraits = package.enabledTraits else {
                        XCTFail("No enabled traits on ChildPackage")
                        return
                    }

                    // Should contain Feature1 from default trait (enabled by Parent2)
                    XCTAssertEqual(enabledTraits, ["Feature1"])

                    // Verify the dependency on GuardedDependency is included
                    let deps = package.dependencies
                    XCTAssertEqual(deps, [PackageIdentity(urlString: "./GuardedDependency")])
                }

                // The graph should include GuardedDependency since Feature1 is enabled
                result.check(modules: "RootTarget", "Parent1Target", "Parent2Target", "ChildTarget", "GuardedTarget")
            }
        }
    }
}
