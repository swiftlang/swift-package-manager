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

import Testing

@testable import SwiftBuildSupport
import Basics
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph
import PackageLoading
import PackageModel
@testable import SwiftBuild
import _InternalTestSupport

@Suite
struct HostOnlyReachabilityTests {

    /// T1 — `macrosPackageGraph()` fixture (swift-firmware root → swift-mmio → swift-syntax).
    /// MMIOMacros is inherently host-only (macro). SwiftSyntax is reachable ONLY via
    /// MMIOMacros → must be in host-only set. Everything else target-reachable.
    @Test
    func macrosGraphHostOnlyReachable() throws {
        let graph = try macrosPackageGraph().graph
        let hostOnly = PackagePIFBuilder.computeHostOnlyReachableModules(in: graph)

        let hostOnlyNames = Set(graph.reachableModules
            .filter { hostOnly.contains($0.id) }
            .map(\.name))

        #expect(hostOnlyNames.contains("MMIOMacros"))
        #expect(hostOnlyNames.contains("SwiftSyntax"))
        #expect(!hostOnlyNames.contains("Core"))
        #expect(!hostOnlyNames.contains("HAL"))
        #expect(!hostOnlyNames.contains("MMIO"))
        #expect(!hostOnlyNames.contains("CoreTests"))
        #expect(!hostOnlyNames.contains("HALTests"))
        #expect(!hostOnlyNames.contains("SwiftSyntaxTests"))
    }

    /// T2 — JS Kit-like topology: a root library, a plugin that depends on an executable
    /// tool, that tool depends on swift-syntax. The tool and its swift-syntax transitive
    /// deps must be host-only; the root library and its tests are not.
    @Test
    func pluginToolChainIsHostOnly() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/my-app/Sources/MyApp/source.swift",
            "/my-app/Sources/MyTool/source.swift",
            "/my-app/Plugins/MyBuildPlugin/source.swift",
            "/my-app/Tests/MyAppTests/source.swift",
            "/swift-syntax/Sources/SwiftSyntax/source.swift",
            "/swift-syntax/Sources/SwiftCompilerPluginMessageHandling/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "my-app",
                    path: "/my-app",
                    dependencies: [
                        .localSourceControl(
                            path: "/swift-syntax",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    products: [
                        ProductDescription(name: "MyApp", type: .library(.automatic), targets: ["MyApp"]),
                        ProductDescription(name: "MyBuildPlugin", type: .plugin, targets: ["MyBuildPlugin"]),
                    ],
                    targets: [
                        TargetDescription(name: "MyApp"),
                        TargetDescription(
                            name: "MyBuildPlugin",
                            dependencies: [.target(name: "MyTool", condition: nil)],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                        TargetDescription(
                            name: "MyTool",
                            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax", condition: nil)],
                            type: .executable
                        ),
                        TargetDescription(
                            name: "MyAppTests",
                            dependencies: [.target(name: "MyApp", condition: nil)],
                            type: .test
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "swift-syntax",
                    path: "/swift-syntax",
                    products: [
                        ProductDescription(
                            name: "SwiftSyntax",
                            type: .library(.automatic),
                            targets: ["SwiftSyntax"]
                        ),
                        ProductDescription(
                            name: "SwiftCompilerPluginMessageHandling",
                            type: .library(.automatic),
                            targets: ["SwiftCompilerPluginMessageHandling"]
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntax", dependencies: []),
                        TargetDescription(
                            name: "SwiftCompilerPluginMessageHandling",
                            dependencies: [.target(name: "SwiftSyntax", condition: nil)]
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let hostOnly = PackagePIFBuilder.computeHostOnlyReachableModules(in: graph)
        let hostOnlyNames = Set(graph.reachableModules
            .filter { hostOnly.contains($0.id) }
            .map(\.name))

        // Plugin tool and its transitive deps → host-only.
        #expect(hostOnlyNames.contains("MyTool"))
        #expect(hostOnlyNames.contains("MyBuildPlugin"))
        #expect(hostOnlyNames.contains("SwiftSyntax"))

        // Consumer-facing library and test (no macro dep) → NOT host-only.
        #expect(!hostOnlyNames.contains("MyApp"))
        #expect(!hostOnlyNames.contains("MyAppTests"))
    }

    /// T3 — a library reachable from BOTH a host-only chain (via a macro) AND a
    /// target-destination chain (as a direct dep of another library). Must NOT be
    /// in host-only set; target-destination reachability wins.
    @Test
    func mixedConsumerIsTargetReachable() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Sources/LibA/source.swift",
            "/pkg/Sources/LibB/source.swift",
            "/pkg/Sources/SharedLib/source.swift",
            "/pkg/Sources/MyMacro/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "pkg",
                    path: "/pkg",
                    products: [
                        ProductDescription(name: "LibA", type: .library(.automatic), targets: ["LibA"]),
                        ProductDescription(name: "LibB", type: .library(.automatic), targets: ["LibB"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "LibA",
                            dependencies: [
                                .target(name: "SharedLib", condition: nil),
                                .target(name: "MyMacro", condition: nil),
                            ]
                        ),
                        TargetDescription(
                            name: "LibB",
                            dependencies: [.target(name: "SharedLib", condition: nil)]
                        ),
                        TargetDescription(name: "SharedLib"),
                        TargetDescription(
                            name: "MyMacro",
                            dependencies: [.target(name: "SharedLib", condition: nil)],
                            type: .macro
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let hostOnly = PackagePIFBuilder.computeHostOnlyReachableModules(in: graph)
        let hostOnlyNames = Set(graph.reachableModules
            .filter { hostOnly.contains($0.id) }
            .map(\.name))

        #expect(hostOnlyNames.contains("MyMacro"))
        // SharedLib reached via LibA (target) AND LibB (target). MUST NOT be host-only.
        #expect(!hostOnlyNames.contains("SharedLib"))
        #expect(!hostOnlyNames.contains("LibA"))
        #expect(!hostOnlyNames.contains("LibB"))
    }

    /// T4 — end-to-end PIF emission. Using the JS Kit-like topology, generate
    /// the PIF via `PIFBuilder.constructPIF(...)` and inspect per-target
    /// `SUPPORTED_PLATFORMS`. Plugin-tool-reachable-only modules must be
    /// host-restricted; the root library must not.
    @Test
    func pifEmissionRestrictsPlatformsForHostOnlyModules() async throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/my-app/Sources/MyApp/source.swift",
            "/my-app/Sources/MyTool/source.swift",
            "/my-app/Plugins/MyBuildPlugin/source.swift",
            "/swift-syntax/Sources/SwiftSyntax/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting(verbose: false)
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "my-app",
                    path: "/my-app",
                    dependencies: [
                        .localSourceControl(
                            path: "/swift-syntax",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    products: [
                        ProductDescription(name: "MyApp", type: .library(.automatic), targets: ["MyApp"]),
                        ProductDescription(name: "MyBuildPlugin", type: .plugin, targets: ["MyBuildPlugin"]),
                    ],
                    targets: [
                        TargetDescription(name: "MyApp"),
                        TargetDescription(
                            name: "MyBuildPlugin",
                            dependencies: [.target(name: "MyTool", condition: nil)],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                        TargetDescription(
                            name: "MyTool",
                            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax", condition: nil)],
                            type: .executable
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "swift-syntax",
                    path: "/swift-syntax",
                    products: [
                        ProductDescription(
                            name: "SwiftSyntax",
                            type: .library(.automatic),
                            targets: ["SwiftSyntax"]
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntax", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild),
            hostBuildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        // Find SUPPORTED_PLATFORMS for the Debug config of any target whose
        // name matches `name` exactly. Accepts both the per-module name (used
        // for library targets) and product-suffixed variants (used for
        // executable products).
        func supportedPlatforms(forTargetMatching name: String) -> [String]? {
            for project in pif.workspace.projects {
                for target in project.underlying.targets where target.common.name == name {
                    for config in target.common.buildConfigs where config.name == "Debug" {
                        return config.settings[.SUPPORTED_PLATFORMS]
                    }
                }
            }
            return nil
        }

        // Diagnostic: log all targets and configs when the test fails.
        func dumpAllTargets() -> String {
            var s = ""
            for project in pif.workspace.projects {
                s += "Project: \(project.underlying.name)\n"
                for target in project.underlying.targets {
                    s += "  Target name='\(target.common.name)' id='\(target.common.id.value)'\n"
                    for config in target.common.buildConfigs {
                        s += "    Config '\(config.name)' SUPPORTED_PLATFORMS=\(config.settings[.SUPPORTED_PLATFORMS] ?? [])\n"
                    }
                }
            }
            return s
        }

        // MyTool is an executable; only emitted as a product target named
        // "MyTool-product". Must be host-restricted.
        #expect(supportedPlatforms(forTargetMatching: "MyTool-product") == ["$(HOST_PLATFORM)"],
                "MyTool-product SUPPORTED_PLATFORMS mismatch. All targets:\n\(dumpAllTargets())")

        // SwiftSyntax is a library; emitted as a per-module target named
        // "SwiftSyntax". Must be host-restricted.
        #expect(supportedPlatforms(forTargetMatching: "SwiftSyntax") == ["$(HOST_PLATFORM)"],
                "SwiftSyntax SUPPORTED_PLATFORMS mismatch. All targets:\n\(dumpAllTargets())")

        // MyApp is a library reachable from a non-host context; must NOT be
        // host-restricted.
        #expect(supportedPlatforms(forTargetMatching: "MyApp") != ["$(HOST_PLATFORM)"])
    }

    /// T5 — safety: a root executable that has no consumers (not a plugin
    /// tool) must not cause `computePluginTools` to loop or misclassify.
    /// Asserts termination and correct classification.
    @Test
    func leafRootExecutableIsNotHostOnly() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/Sources/MyExec/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "pkg",
                    path: "/pkg",
                    products: [
                        ProductDescription(name: "MyExec", type: .executable, targets: ["MyExec"]),
                    ],
                    targets: [
                        TargetDescription(name: "MyExec", type: .executable),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        // Completes without hanging. MyExec has no consumers → NOT a plugin tool
        // → target-reachable via root-package seeding.
        let hostOnly = PackagePIFBuilder.computeHostOnlyReachableModules(in: graph)
        let hostOnlyNames = Set(graph.reachableModules
            .filter { hostOnly.contains($0.id) }
            .map(\.name))
        #expect(!hostOnlyNames.contains("MyExec"))
    }
}
