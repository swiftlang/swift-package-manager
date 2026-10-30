//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph
import PackageLoading
import PackageModel
import TSCUtility
import _InternalTestSupport
import Testing

@Suite
struct PublicTargetModuleAliasingTests {
    private func module(_ name: String, in package: String, of graph: ModulesGraph) throws -> ResolvedModule {
        try #require(graph.package(for: .plain(package))?.modules.first { $0.name == name })
    }

    @Test
    func aliasOnPublicTargetDependency() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Root/Sources/Utils/file.swift",
            "/Dep/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    targets: [
                        TargetDescription(name: "Utils", visibility: .public),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                "Utils",
                                .target(name: "Utils", package: "Dep", moduleAliases: ["Utils": "DepUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let depUtils = try module("DepUtils", in: "Dep", of: graph)
        #expect(depUtils.moduleAliases == ["Utils": "DepUtils"])
        let rootUtils = try module("Utils", in: "Root", of: graph)
        #expect(rootUtils.moduleAliases == nil)
        let exe = try module("exe", in: "Root", of: graph)
        #expect(Set(exe.dependencies.compactMap(\.module).map(\.name)) == ["Utils", "DepUtils"])
    }

    @Test
    func aliasPropagatesToDependentsInSamePackage() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Root/Sources/Utils/file.swift",
            "/Dep/Sources/Lib/file.swift",
            "/Dep/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    targets: [
                        TargetDescription(name: "Lib", dependencies: ["Utils"], visibility: .public),
                        TargetDescription(name: "Utils"),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                "Utils",
                                .target(name: "Lib", package: "Dep", moduleAliases: ["Utils": "DepUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let depUtils = try module("DepUtils", in: "Dep", of: graph)
        #expect(depUtils.moduleAliases == ["Utils": "DepUtils"])
        let lib = try module("Lib", in: "Dep", of: graph)
        #expect(lib.moduleAliases == ["Utils": "DepUtils"])
        #expect(try module("Utils", in: "Root", of: graph).moduleAliases == nil)
    }

    @Test
    func chainedAliasesThroughIntermediatePublicTarget() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/App/Sources/App/main.swift",
            "/App/Sources/Utils/file.swift",
            "/Lib/Sources/Lib/file.swift",
            "/Game/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Game",
                    path: "/Game",
                    targets: [
                        TargetDescription(name: "Utils", visibility: .public),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Lib",
                    path: "/Lib",
                    dependencies: [
                        .localSourceControl(path: "/Game", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Lib",
                            dependencies: [
                                .target(name: "Utils", package: "Game", moduleAliases: ["Utils": "GameUtils"], condition: nil),
                            ],
                            visibility: .public
                        ),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "App",
                    path: "/App",
                    dependencies: [
                        .localSourceControl(path: "/Lib", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "App",
                            dependencies: [
                                "Utils",
                                .target(name: "Lib", package: "Lib", moduleAliases: ["GameUtils": "LibUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let gameUtils = try module("LibUtils", in: "Game", of: graph)
        #expect(gameUtils.moduleAliases == ["Utils": "LibUtils"])
        let lib = try module("Lib", in: "Lib", of: graph)
        #expect(lib.moduleAliases?["Utils"] == "LibUtils")
        #expect(try module("Utils", in: "App", of: graph).moduleAliases == nil)
    }

    @Test
    func chainedAliasesThroughByNameDependencyOnPublicTarget() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/App/Sources/App/main.swift",
            "/App/Sources/Utils/file.swift",
            "/Lib/Sources/Lib/file.swift",
            "/Utils/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Utils",
                    path: "/Utils",
                    targets: [
                        TargetDescription(name: "Utils", visibility: .public),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Lib",
                    path: "/Lib",
                    dependencies: [
                        .localSourceControl(path: "/Utils", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Lib", dependencies: ["Utils"], visibility: .public),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "App",
                    path: "/App",
                    dependencies: [
                        .localSourceControl(path: "/Lib", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "App",
                            dependencies: [
                                "Utils",
                                .target(name: "Lib", package: "Lib", moduleAliases: ["Utils": "LibUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let libUtils = try module("LibUtils", in: "Utils", of: graph)
        #expect(libUtils.moduleAliases == ["Utils": "LibUtils"])
        let lib = try module("Lib", in: "Lib", of: graph)
        #expect(lib.moduleAliases?["Utils"] == "LibUtils")
        #expect(try module("Utils", in: "App", of: graph).moduleAliases == nil)
    }

    @Test
    func chainedAliasesMixingProductAndTargetDependencies() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/App/Sources/App/main.swift",
            "/App/Sources/Utils/file.swift",
            "/Lib/Sources/Lib/file.swift",
            "/Game/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Game",
                    path: "/Game",
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["Utils"]),
                    ],
                    targets: [
                        TargetDescription(name: "Utils"),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Lib",
                    path: "/Lib",
                    dependencies: [
                        .localSourceControl(path: "/Game", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Lib",
                            dependencies: [
                                .product(name: "Utils", package: "Game", moduleAliases: ["Utils": "GameUtils"]),
                            ],
                            visibility: .public
                        ),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "App",
                    path: "/App",
                    dependencies: [
                        .localSourceControl(path: "/Lib", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "App",
                            dependencies: [
                                "Utils",
                                .target(name: "Lib", package: "Lib", moduleAliases: ["GameUtils": "LibUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let gameUtils = try module("LibUtils", in: "Game", of: graph)
        #expect(gameUtils.moduleAliases == ["Utils": "LibUtils"])
        let lib = try module("Lib", in: "Lib", of: graph)
        #expect(lib.moduleAliases?["Utils"] == "LibUtils")
    }

    @Test
    func aliasOnProductDependencyThatFallsBackToPublicTarget() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Root/Sources/Utils/file.swift",
            "/Dep/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    targets: [
                        TargetDescription(name: "Utils", visibility: .public),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                "Utils",
                                .product(name: "Utils", package: "Dep", moduleAliases: ["Utils": "DepUtils"]),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Utils"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let depUtils = try module("DepUtils", in: "Dep", of: graph)
        #expect(depUtils.moduleAliases == ["Utils": "DepUtils"])
        let exe = try module("exe", in: "Root", of: graph)
        #expect(Set(exe.dependencies.compactMap(\.module).map(\.name)) == ["Utils", "DepUtils"])
    }

    @Test
    func aliasOnMemberOfAggregateLibraryTarget() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Root/Sources/Member/file.swift",
            "/Dep/Sources/Member/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    toolsVersion: .vNext,
                    targets: [
                        TargetDescription(name: "Member"),
                        TargetDescription(name: "Aggregate", dependencies: ["Member"], type: .library(.static), visibility: .public),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                "Member",
                                .target(name: "Aggregate", package: "Dep", moduleAliases: ["Member": "DepMember"], condition: nil),
                            ],
                            type: .executable
                        ),
                        TargetDescription(name: "Member"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        expectNoDiagnostics(observability.diagnostics)

        let depMember = try module("DepMember", in: "Dep", of: graph)
        #expect(depMember.moduleAliases == ["Member": "DepMember"])
        let aggregate = try module("Aggregate", in: "Dep", of: graph)
        #expect(aggregate.type.isLibraryAggregate)
        #expect(try module("Member", in: "Root", of: graph).moduleAliases == nil)
    }

    @Test
    func aliasOnAggregateLibraryTargetItselfHasNoEffect() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Dep/Sources/Member/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    toolsVersion: .vNext,
                    targets: [
                        TargetDescription(name: "Member"),
                        TargetDescription(name: "Aggregate", dependencies: ["Member"], type: .library(.static), visibility: .public),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                .target(name: "Aggregate", package: "Dep", moduleAliases: ["Aggregate": "DepAggregate"], condition: nil),
                            ],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        try expectDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "module alias for library target 'Aggregate' from package 'dep', declared in package 'root', has no effect; 'Aggregate' has no sources of its own, so alias the targets it depends on instead",
                severity: .warning
            )
        }
        let aggregate = try module("Aggregate", in: "Dep", of: graph)
        #expect(aggregate.moduleAliases == nil)
    }

    @Test
    func conflictingAliasesOnPublicTargetDependency() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Root/Sources/Utils/file.swift",
            "/Dep/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        #expect {
            try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createFileSystemManifest(
                        displayName: "Dep",
                        path: "/Dep",
                        targets: [
                            TargetDescription(name: "Utils", visibility: .public),
                        ]
                    ),
                    Manifest.createRootManifest(
                        displayName: "Root",
                        path: "/Root",
                        dependencies: [
                            .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                        ],
                        targets: [
                            TargetDescription(
                                name: "exe",
                                dependencies: [
                                    "Utils",
                                    .target(name: "Utils", package: "Dep", moduleAliases: ["Utils": "DepUtils"], condition: nil),
                                ],
                                type: .executable
                            ),
                            TargetDescription(
                                name: "Utils",
                                dependencies: [
                                    .target(name: "Utils", package: "Dep", moduleAliases: ["Utils": "OtherUtils"], condition: nil),
                                ]
                            ),
                        ]
                    ),
                ],
                observabilityScope: observability.topScope
            )
        } throws: { error in
            "\(error)".contains("found for target 'Utils' in target 'Utils' from package")
        }
    }

    @Test
    func aliasOnPackageVisibleTargetDependency() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Root/Sources/exe/main.swift",
            "/Dep/Sources/Utils/file.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    targets: [
                        TargetDescription(name: "Utils"),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [
                                .target(name: "Utils", package: "Dep", moduleAliases: ["Utils": "DepUtils"], condition: nil),
                            ],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        // The visibility problem is reported by the modules graph rather than as an unmatched alias.
        try expectDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: "target 'Utils' required by target 'exe' not found in package 'Dep'",
                severity: .error
            )
        }
    }
}
