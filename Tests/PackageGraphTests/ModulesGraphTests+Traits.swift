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

import Basics
import PackageModel
import TSCUtility
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

extension ModulesGraphTests {
    @Test
    func traits_whenSingleManifest_andDefaultTrait() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Foo/Sources/Foo/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: "/Foo",
                    toolsVersion: .v5_9,
                    targets: [
                        TargetDescription(
                            name: "Foo"
                        ),
                    ],
                    traits: [
                        .init(name: "default", enabledTraits: ["Trait1"]),
                        "Trait1",
                    ]
                ),
            ],
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Foo": ["Trait1"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Foo") { package in
                #expect(package.enabledTraits == ["Trait1"])
            }
        }
    }

    @Test
    func traits_whenTraitEnablesOtherTraits() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Foo/Sources/Foo/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: "/Foo",
                    toolsVersion: .v5_9,
                    targets: [
                        TargetDescription(
                            name: "Foo"
                        ),
                    ],
                    traits: [
                        .init(name: "default", enabledTraits: ["Trait1"]),
                        .init(name: "Trait1", enabledTraits: ["Trait2"]),
                        .init(name: "Trait2", enabledTraits: ["Trait3", "Trait4"]),
                        "Trait3",
                        .init(name: "Trait4", enabledTraits: ["Trait5"]),
                        "Trait5",
                    ]
                ),
            ],
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Foo": ["Trait1", "Trait2", "Trait3", "Trait4", "Trait5"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Foo") { package in
                #expect(package.enabledTraits == ["Trait1", "Trait2", "Trait3", "Trait4", "Trait5"])
            }
        }
    }

    @Test
    func traits_whenDependencyTraitEnabled() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Package1/Sources/Package1Target1/source.swift",
            "/Package2/Sources/Package2Target1/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Package1",
                    path: "/Package1",
                    toolsVersion: .v5_9,
                    dependencies: [
                        .localSourceControl(
                            path: "/Package2",
                            requirement: .upToNextMajor(from: "1.0.0"),
                            traits: ["Package2Trait1"]
                        ),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Package1Target1",
                            dependencies: [
                                .product(name: "Package2Target1", package: "Package2"),
                            ]
                        ),
                    ],
                    traits: [
                        .init(name: "default", enabledTraits: ["Package1Trait1"]),
                        "Package1Trait1",
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Package2",
                    path: "/Package2",
                    toolsVersion: .v5_9,
                    products: [
                        .init(
                            name: "Package2Target1",
                            type: .library(.automatic),
                            targets: ["Package2Target1"]
                        ),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Package2Target1"
                        ),
                    ],
                    traits: [
                        "Package2Trait1",
                    ]
                ),
            ],
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Package1": ["Package1Trait1"],
                "Package2": ["Package2Trait1"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Package1") { package in
                #expect(package.enabledTraits == ["Package1Trait1"])
                #expect(package.dependencies.count == 1)
            }
            try result.checkPackage("Package2") { package in
                #expect(package.enabledTraits == ["Package2Trait1"])
            }
        }
    }

    @Test
    func traits_whenTraitEnablesDependencyTrait() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Package1/Sources/Package1Target1/source.swift",
            "/Package2/Sources/Package2Target1/source.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Package1",
                path: "/Package1",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package2",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package2Trait1", condition: .init(traits: ["Package1Trait1"]))])
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package1Target1",
                        dependencies: [
                            .product(name: "Package2Target1", package: "Package2"),
                        ]
                    ),
                ],
                traits: [
                    .init(name: "default", enabledTraits: ["Package1Trait1"]),
                    .init(name: "Package1Trait1"),
                ]
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package2",
                path: "/Package2",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package2Target1",
                        type: .library(.automatic),
                        targets: ["Package2Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package2Target1"
                    ),
                ],
                traits: [
                    "Package2Trait1",
                ]
            ),
        ]
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Package1": ["Package1Trait1"],
                "Package2": ["Package2Trait1"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Package1") { package in
                #expect(package.enabledTraits == ["Package1Trait1"])
                #expect(package.dependencies.count == 1)
            }
            try result.checkPackage("Package2") { package in
                #expect(package.enabledTraits == ["Package2Trait1"])
            }
        }
    }

    @Test
    func traits_whenComplex() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Package1/Sources/Package1Target1/source.swift",
            "/Package2/Sources/Package2Target1/source.swift",
            "/Package3/Sources/Package3Target1/source.swift",
            "/Package4/Sources/Package4Target1/source.swift",
            "/Package5/Sources/Package5Target1/source.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Package1",
                path: "/Package1",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package2",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package2Trait1", condition: .init(traits: ["Package1Trait1"]))])
                    ),
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init(["Package4Trait2"])
                    ),
                    .localSourceControl(
                        path: "/Package5",
                        requirement: .upToNextMajor(from: "1.0.0")
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package1Target1",
                        dependencies: [
                            .product(name: "Package2Target1", package: "Package2"),
                            .product(name: "Package4Target1", package: "Package4"),
                            .product(
                                name: "Package5Target1",
                                package: "Package5",
                                condition: .init(traits: ["Package1Trait2"])
                            ),
                        ],
                        settings: [
                            .init(
                                tool: .swift,
                                kind: .define("TEST_DEFINE"),
                                condition: .init(traits: ["Package1Trait1"])
                            ),
                        ]
                    ),
                ],
                traits: [
                    .init(name: "default", enabledTraits: ["Package1Trait1", "Package1Trait2"]),
                    .init(name: "Package1Trait1"),
                    .init(name: "Package1Trait2"),
                ]
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package2",
                path: "/Package2",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package3",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package3Trait1", condition: .init(traits: ["Package2Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package2Target1",
                        type: .library(.automatic),
                        targets: ["Package2Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package2Target1",
                        dependencies: [
                            .product(name: "Package3Target1", package: "Package3"),
                        ]
                    ),
                ],
                traits: [
                    "Package2Trait1",
                ]
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package3",
                path: "/Package3",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package4Trait1", condition: .init(traits: ["Package3Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package3Target1",
                        type: .library(.automatic),
                        targets: ["Package3Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package3Target1",
                        dependencies: [
                            .product(name: "Package4Target1", package: "Package4"),
                        ]
                    ),
                ],
                traits: [
                    "Package3Trait1",
                ]
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package4",
                path: "/Package4",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package4Target1",
                        type: .library(.automatic),
                        targets: ["Package4Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package4Target1"
                    ),
                ],
                traits: [
                    "Package4Trait1",
                    "Package4Trait2",
                ]
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package5",
                path: "/Package5",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package5Target1",
                        type: .library(.automatic),
                        targets: ["Package5Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package5Target1"
                    ),
                ]
            ),
        ]
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Package1": ["Package1Trait1", "Package1Trait2"],
                "Package2": ["Package2Trait1"],
                "Package3": ["Package3Trait1"],
                "Package4": ["Package4Trait1", "Package4Trait2"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Package1") { package in
                #expect(package.enabledTraits == ["Package1Trait1", "Package1Trait2"])
                #expect(package.dependencies.count == 3)
            }
            try result.checkTarget("Package1Target1") { target in
                target.check(dependencies: "Package2Target1", "Package4Target1", "Package5Target1")
                target.checkBuildSetting(
                    declaration: .SWIFT_ACTIVE_COMPILATION_CONDITIONS,
                    assignments: [
                        .init(values: ["TEST_DEFINE"], conditions: [.traits(.init(traits: ["Package1Trait1"]))]),
                        .init(values: ["Package1Trait2"]),
                        .init(values: ["Package1Trait1"]),
                    ]
                )
            }
            try result.checkPackage("Package2") { package in
                #expect(package.enabledTraits == ["Package2Trait1"])
            }
            try result.checkPackage("Package3") { package in
                #expect(package.enabledTraits == ["Package3Trait1"])
            }
            try result.checkPackage("Package4") { package in
                #expect(package.enabledTraits == ["Package4Trait1", "Package4Trait2"])
            }
        }
    }

    @Test
    func traits_whenPruneDependenciesEnabled() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Package1/Sources/Package1Target1/source.swift",
            "/Package2/Sources/Package2Target1/source.swift",
            "/Package3/Sources/Package3Target1/source.swift",
            "/Package4/Sources/Package4Target1/source.swift",
            "/Package5/Sources/Package5Target1/source.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Package1",
                path: "/Package1",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package2",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package2Trait1", condition: .init(traits: ["Package1Trait1"]))])
                    ),
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init(["Package4Trait2"])
                    ),
                    .localSourceControl(
                        path: "/Package5",
                        requirement: .upToNextMajor(from: "1.0.0")
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package1Target1",
                        dependencies: [
                            .product(name: "Package2Target1", package: "Package2"),
                            .product(name: "Package4Target1", package: "Package4"),
                            .product(
                                name: "Package5Target1",
                                package: "Package5",
                                condition: .init(traits: ["Package1Trait2"])
                            ),
                        ],
                        settings: [
                            .init(
                                tool: .swift,
                                kind: .define("TEST_DEFINE"),
                                condition: .init(traits: ["Package1Trait1"])
                            ),
                            .init(
                                tool: .swift,
                                kind: .define("TEST_DEFINE_2"),
                                condition: .init(traits: ["Package1Trait3"])
                            ),
                        ]
                    ),
                ],
                traits: [
                    .init(name: "default", enabledTraits: ["Package1Trait3"]),
                    .init(name: "Package1Trait1"),
                    .init(name: "Package1Trait2"),
                    .init(name: "Package1Trait3"),
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package2",
                path: "/Package2",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package3",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package3Trait1", condition: .init(traits: ["Package2Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package2Target1",
                        type: .library(.automatic),
                        targets: ["Package2Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package2Target1",
                        dependencies: [
                            .product(name: "Package3Target1", package: "Package3"),
                        ]
                    ),
                ],
                traits: [
                    "Package2Trait1",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package3",
                path: "/Package3",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package4Trait1", condition: .init(traits: ["Package3Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package3Target1",
                        type: .library(.automatic),
                        targets: ["Package3Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package3Target1",
                        dependencies: [
                            .product(name: "Package4Target1", package: "Package4"),
                        ]
                    ),
                ],
                traits: [
                    "Package3Trait1",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package4",
                path: "/Package4",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package4Target1",
                        type: .library(.automatic),
                        targets: ["Package4Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package4Target1"
                    ),
                ],
                traits: [
                    "Package4Trait1",
                    "Package4Trait2",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package5",
                path: "/Package5",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package5Target1",
                        type: .library(.automatic),
                        targets: ["Package5Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package5Target1"
                    ),
                ],
                pruneDependencies: true
            ),
        ]
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Package1": ["Package1Trait3"],
                "Package2": [],
                "Package3": [],
                "Package4": ["Package4Trait2"]
            ]
        )

        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graph) { result in
            try result.checkPackage("Package1") { package in
                #expect(package.enabledTraits == ["Package1Trait3"])
                #expect(package.dependencies.count == 2)
            }
            try result.checkTarget("Package1Target1") { target in
                target.check(dependencies: "Package2Target1", "Package4Target1")
                target.checkBuildSetting(
                    declaration: .SWIFT_ACTIVE_COMPILATION_CONDITIONS,
                    assignments: [
                        .init(values: ["TEST_DEFINE_2"], conditions: [.traits(.init(traits: ["Package1Trait3"]))]),
                        .init(values: ["Package1Trait3"]),
                    ]
                )
            }
            try result.checkPackage("Package2") { package in
                #expect(package.enabledTraits == [])
            }
            try result.checkPackage("Package3") { package in
                #expect(package.enabledTraits == [])
            }
            try result.checkPackage("Package4") { package in
                #expect(package.enabledTraits == ["Package4Trait2"])
            }
        }
    }

    @Test
    func traits_whenPruneDependenciesEnabledForSomeManifests() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Package1/Sources/Package1Target1/source.swift",
            "/Package2/Sources/Package2Target1/source.swift",
            "/Package3/Sources/Package3Target1/source.swift",
            "/Package4/Sources/Package4Target1/source.swift",
            "/Package5/Sources/Package5Target1/source.swift"
        )

        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Package1",
                path: "/Package1",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package2",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package2Trait1", condition: .init(traits: ["Package1Trait1"]))])
                    ),
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init(["Package4Trait2"])
                    ),
                    .localSourceControl(
                        path: "/Package5",
                        requirement: .upToNextMajor(from: "1.0.0")
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package1Target1",
                        dependencies: [
                            .product(name: "Package2Target1", package: "Package2"),
                            .product(name: "Package4Target1", package: "Package4"),
                            .product(
                                name: "Package5Target1",
                                package: "Package5",
                                condition: .init(traits: ["Package1Trait2"])
                            ),
                        ],
                        settings: [
                            .init(
                                tool: .swift,
                                kind: .define("TEST_DEFINE"),
                                condition: .init(traits: ["Package1Trait1"])
                            ),
                            .init(
                                tool: .swift,
                                kind: .define("TEST_DEFINE_2"),
                                condition: .init(traits: ["Package1Trait3"])
                            ),
                        ]
                    ),
                ],
                traits: [
                    .init(name: "default", enabledTraits: ["Package1Trait3"]),
                    .init(name: "Package1Trait1"),
                    .init(name: "Package1Trait2"),
                    .init(name: "Package1Trait3"),
                ],
                pruneDependencies: false
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package2",
                path: "/Package2",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package3",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package3Trait1", condition: .init(traits: ["Package2Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package2Target1",
                        type: .library(.automatic),
                        targets: ["Package2Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package2Target1",
                        dependencies: [
                            .product(name: "Package3Target1", package: "Package3"),
                        ]
                    ),
                ],
                traits: [
                    "Package2Trait1",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package3",
                path: "/Package3",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Package4",
                        requirement: .upToNextMajor(from: "1.0.0"),
                        traits: .init([.init(name: "Package4Trait1", condition: .init(traits: ["Package3Trait1"]))])
                    ),
                ],
                products: [
                    .init(
                        name: "Package3Target1",
                        type: .library(.automatic),
                        targets: ["Package3Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package3Target1",
                        dependencies: [
                            .product(name: "Package4Target1", package: "Package4"),
                        ]
                    ),
                ],
                traits: [
                    "Package3Trait1",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package4",
                path: "/Package4",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package4Target1",
                        type: .library(.automatic),
                        targets: ["Package4Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package4Target1"
                    ),
                ],
                traits: [
                    "Package4Trait1",
                    "Package4Trait2",
                ],
                pruneDependencies: true
            ),
            Manifest.createFileSystemManifest(
                displayName: "Package5",
                path: "/Package5",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Package5Target1",
                        type: .library(.automatic),
                        targets: ["Package5Target1"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "Package5Target1"
                    ),
                ],
                pruneDependencies: true
            ),
        ]
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Package1": ["Package1Trait3"],
                "Package2": [],
                "Package3": [],
                "Package4": ["Package4Trait2"]
            ]
        )

        #expect(observability.diagnostics.count == 0)
        try PackageGraphTester(graph) { result in
            try result.checkPackage("Package1") { package in
                #expect(package.enabledTraits == ["Package1Trait3"])
                #expect(package.dependencies.count == 2)
            }
            try result.checkTarget("Package1Target1") { target in
                target.check(dependencies: "Package2Target1", "Package4Target1")
                target.checkBuildSetting(
                    declaration: .SWIFT_ACTIVE_COMPILATION_CONDITIONS,
                    assignments: [
                        .init(values: ["TEST_DEFINE_2"], conditions: [.traits(.init(traits: ["Package1Trait3"]))]),
                        .init(values: ["Package1Trait3"]),
                    ]
                )
            }
            try result.checkPackage("Package2") { package in
                #expect(package.enabledTraits == [])
            }
            try result.checkPackage("Package3") { package in
                #expect(package.enabledTraits == [])
            }
            try result.checkPackage("Package4") { package in
                #expect(package.enabledTraits == ["Package4Trait2"])
            }
        }
    }

    @Test
    func traits_whenConditionalDependencies() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Lunch/Sources/Drink/source.swift",
            "/Caffeine/Sources/CoffeeTarget/source.swift",
            "/Juice/Sources/AppleJuiceTarget/source.swift",
        )

        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Lunch",
                path: "/Lunch",
                toolsVersion: .v5_9,
                dependencies: [
                    .localSourceControl(
                        path: "/Caffeine",
                        requirement: .upToNextMajor(from: "1.0.0"),
                    ),
                    .localSourceControl(
                        path: "/Juice",
                        requirement: .upToNextMajor(from: "1.0.0")
                    )
                ],
                targets: [
                    TargetDescription(
                        name: "Drink",
                        dependencies: [
                            .product(
                                name: "Coffee",
                                package: "Caffeine",
                                condition: .init(traits: ["EnableCoffeeDep"])
                            ),
                            .product(
                                name: "AppleJuice",
                                package: "Juice",
                                condition: .init(traits: ["EnableAppleJuiceDep"])
                            )
                        ],
                    ),
                ],
                traits: [
                    .init(name: "default", enabledTraits: ["EnableCoffeeDep"]),
                    .init(name: "EnableCoffeeDep"),
                    .init(name: "EnableAppleJuiceDep"),
                ],
            ),
            Manifest.createFileSystemManifest(
                displayName: "Caffeine",
                path: "/Caffeine",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "Coffee",
                        type: .library(.automatic),
                        targets: ["CoffeeTarget"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "CoffeeTarget",
                    ),
                ],
            ),
            Manifest.createFileSystemManifest(
                displayName: "Juice",
                path: "/Juice",
                toolsVersion: .v5_9,
                products: [
                    .init(
                        name: "AppleJuice",
                        type: .library(.automatic),
                        targets: ["AppleJuiceTarget"]
                    ),
                ],
                targets: [
                    TargetDescription(
                        name: "AppleJuiceTarget",
                    ),
                ],
            )
        ]

        // Test graph with default trait configuration
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            enabledTraitsMap: [
                "Lunch": ["EnableCoffeeDep"]
            ]
        )

        #expect(observability.diagnostics.count == 0)
        try PackageGraphTester(graph) { result in
            try result.checkPackage("Lunch") { package in
                #expect(package.enabledTraits == ["EnableCoffeeDep"])
                #expect(package.dependencies.count == 1)
            }
            try result.checkTarget("Drink") { target in
                target.check(dependencies: "Coffee")
            }
            try result.checkPackage("Caffeine") { package in
                #expect(package.enabledTraits == ["default"])
            }
            try result.checkPackage("Juice") { package in
                #expect(package.enabledTraits == ["default"])
            }
        }

        // Test graph when disabling all traits
        let graphWithTraitsDisabled = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            traitConfiguration: .disableAllTraits,
            enabledTraitsMap: [
                "Lunch": [],
            ]
        )
        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graphWithTraitsDisabled) { result in
            try result.checkPackage("Lunch") { package in
                #expect(package.enabledTraits == [])
                #expect(package.dependencies.count == 0)
            }
            try result.checkTarget("Drink") { target in
                #expect(target.target.dependencies.isEmpty)
            }
            try result.checkPackage("Caffeine") { package in
                #expect(package.enabledTraits == ["default"])
            }
            try result.checkPackage("Juice") { package in
                #expect(package.enabledTraits == ["default"])
            }
        }

        // Test graph when we set a trait configuration that enables different traits than the defaults
        let graphWithDifferentEnabledTraits = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: observability.topScope,
            traitConfiguration: .enabledTraits(["EnableAppleJuiceDep"]),
            enabledTraitsMap: [
                "Lunch": ["EnableAppleJuiceDep"],
            ]
        )
        #expect(observability.diagnostics.count == 0)

        try PackageGraphTester(graphWithDifferentEnabledTraits) { result in
            try result.checkPackage("Lunch") { package in
                #expect(package.enabledTraits == ["EnableAppleJuiceDep"])
                #expect(package.dependencies.count == 1)
            }
            try result.checkTarget("Drink") { target in
                target.check(dependencies: "AppleJuice")
            }
            try result.checkPackage("Caffeine") { package in
                #expect(package.enabledTraits == ["default"])
            }
            try result.checkPackage("Juice") { package in
                #expect(package.enabledTraits == ["default"])
            }
        }
    }

}
