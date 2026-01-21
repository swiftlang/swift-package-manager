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
import PackageLoading
import SwiftBuildSupport
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) @testable import PackageGraph
@_spi(SwiftPMInternal) @testable import PackageModel

/// PIF version of the PrebuiltsBuildPlanTests
@Suite
struct PrebuiltsPIFTests {
    // The prebuilts used for these tests
    let prebuiltLibrary = PrebuiltLibrary(
        identity: .plain("swift-syntax"),
        libraryName: "MacroSupport",
        path: "/MyPackage/.build/prebuilts/swift-syntax/600.0.1/6.1-MacroSupport-macos_aarch64",
        checkoutPath: "/MyPackage/.build/checkouts/swift-syntax",
        products: [
            "SwiftBasicFormat",
            "SwiftCompilerPlugin",
            "SwiftDiagnostics",
            "SwiftIDEUtils",
            "SwiftOperators",
            "SwiftParser",
            "SwiftParserDiagnostics",
            "SwiftRefactor",
            "SwiftSyntax",
            "SwiftSyntaxBuilder",
            "SwiftSyntaxMacros",
            "SwiftSyntaxMacroExpansion",
            "SwiftSyntaxMacrosTestSupport",
            "SwiftSyntaxMacrosGenericTestSupport",
            "_SwiftCompilerPluginMessageHandling",
            "_SwiftLibraryPluginProvider",
        ],
        includePath: [
            "Sources/_SwiftSyntaxCShims/include"
        ]
    )

    @Test func testSuccessPath() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPackage/Sources/Base/Base.swift",
                "/MyPackage/Sources/Intermediate/Intermediate.swift",
                "/MyPackage/Sources/Macros/Macros.swift",
                "/MyPackage/Sources/MacroLib/MacroLib.swift",
                "/MyPackage/Sources/Generator/Generator.swift",
                "/MyPackage/Plugins/Plugin/Plugin.swift",
                "/MyRoot/Sources/MyApp/MyApp.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacros/SwiftSyntaxMacros.swift",
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyRoot",
                    path: "/MyRoot",
                    dependencies: [
                        .remoteSourceControl(
                            url: "https://github.com/swiftlang/swift-syntax",
                            requirement: .exact("600.0.1")),
                        .fileSystem(path: "/MyPackage"),
                    ],
                    products: [
                        ProductDescription(
                            name: "MyApp",
                            type: .executable,
                            targets: ["MyApp"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "MyApp",
                            dependencies: [
                                .product(name: "MacroLib", package: "MyPackage")
                            ],
                            type: .executable,
                            pluginUsages: [
                                .plugin(name: "Plugin", package: "MyPackage")
                            ],
                        )
                    ],
                ),
                Manifest.createFileSystemManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    dependencies: [
                        .remoteSourceControl(
                            url: "https://github.com/swiftlang/swift-syntax",
                            requirement: .exact("600.0.1"))
                    ],
                    products: [
                        ProductDescription(
                            name: "MacroLib",
                            type: .library(.automatic),
                            targets: [
                                "MacroLib"
                            ]
                        ),
                        ProductDescription(
                            name: "Plugin",
                            type: .plugin,
                            targets: [
                                "Plugin"
                            ]
                        ),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Base",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
                            ]
                        ),
                        TargetDescription(
                            name: "Intermediate",
                            dependencies: [
                                "Base"
                            ]
                        ),
                        TargetDescription(
                            name: "Macros",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                "Intermediate",
                            ],
                            type: .macro
                        ),
                        TargetDescription(
                            name: "MacroLib",
                            dependencies: [
                                "Macros"
                            ]
                        ),
                        TargetDescription(
                            name: "Generator",
                            dependencies: [
                                "Base"
                            ],
                            type: .executable
                        ),
                        TargetDescription(
                            name: "Plugin",
                            dependencies: [
                                "Generator"
                            ],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ],
                ),
                Manifest.createRemoteSourceControlManifest(
                    displayName: "swift-syntax",
                    url: "https://github.com/swiftlang/swift-syntax",
                    path: "/swift-syntax",
                    products: [
                        ProductDescription(
                            name: "SwiftSyntaxMacros",
                            type: .library(.automatic),
                            targets: ["SwiftSyntaxMacros"]
                        )
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntaxMacros")
                    ]
                ),
            ],
            prebuilts: [
                prebuiltLibrary.identity: prebuiltLibrary.products.reduce(into: [:]) {
                    $0[$1] = prebuiltLibrary
                }
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder: PIFBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root, addLocalRpaths: true),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let pif = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host)
        )

        let hostTargets = Set([
            "Plugin-product",
            "Generator-product",
            "Plugin",
            "Macros",
            "Intermediate",
            "Base",
        ])

        let allPlatTargets = Set([
            "MacroLib-product",
            "MacroLibdynamic-product",
            "MacroLib",
            "MyApp-product",
            "AllIncludingTests",
            "AllExcludingTests",
        ])

        let targets = pif.workspace.projects.flatMap({ $0.underlying.targets })
        for target in targets {
            let isHost: Bool = target.common.buildConfigs.contains {
                guard let platforms = $0.settings[.SUPPORTED_PLATFORMS] else {
                    return false
                }
                return platforms == ["$(HOST_PLATFORM)"]
            }

            if isHost {
                #expect(hostTargets.contains(target.common.name))
            } else {
                #expect(allPlatTargets.contains(target.common.name))
            }
        }
    }

    // Make sure HOST_PLATFORM isn't set if a library leaks out the prebuilts to potential cross builds
    @Test func testLeakyLibrary() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPackage/Sources/Base/Base.swift",
                "/MyPackage/Sources/Intermediate/Intermediate.swift",
                "/MyPackage/Sources/Macros/Macros.swift",
                "/MyPackage/Sources/MacroLib/MacroLib.swift",
                "/MyPackage/Sources/Generator/Generator.swift",
                "/MyPackage/Plugins/Plugin/Plugin.swift",
                "/MyRoot/Sources/MyApp/MyApp.swift",
                "/MyRoot/Sources/LeakyLib/LeakyLib.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacros/SwiftSyntaxMacros.swift",
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyRoot",
                    path: "/MyRoot",
                    dependencies: [
                        .remoteSourceControl(url: "https://github.com/swiftlang/swift-syntax", requirement: .exact("600.0.1")),
                        .fileSystem(path: "/MyPackage"),
                    ],
                    products: [
                        ProductDescription(
                            name: "MyApp",
                            type: .executable,
                            targets: ["MyApp"]
                        ),
                        ProductDescription(
                            name: "LeakyLib",
                            type: .library(.automatic),
                            targets: ["LeakyLib"]
                        ),
                    ],
                    targets: [
                        TargetDescription(
                            name: "MyApp",
                            dependencies: [
                                .product(name: "MacroLib", package: "MyPackage"),
                            ],
                            type: .executable,
                            pluginUsages: [
                                .plugin(name: "Plugin", package: "MyPackage")
                            ],
                        ),
                        TargetDescription(
                            name: "LeakyLib",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                            ]
                        )
                    ],
                ),
                Manifest.createFileSystemManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    dependencies: [
                        .remoteSourceControl(url: "https://github.com/swiftlang/swift-syntax", requirement: .exact("600.0.1")),
                    ],
                    products: [
                        ProductDescription(
                            name: "MacroLib",
                            type: .library(.automatic),
                            targets: [
                                "MacroLib"
                            ]
                        ),
                        ProductDescription(
                            name: "Plugin",
                            type: .plugin,
                            targets: [
                                "Plugin"
                            ]
                        ),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Base",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                            ]
                        ),
                        TargetDescription(
                            name: "Intermediate",
                            dependencies: [
                                "Base"
                            ]
                        ),
                        TargetDescription(
                            name: "Macros",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                "Intermediate",
                            ],
                            type: .macro
                        ),
                        TargetDescription(
                            name: "MacroLib",
                            dependencies: [
                                "Macros"
                            ]
                        ),
                        TargetDescription(
                            name: "Generator",
                            dependencies: [
                                "Base"
                            ],
                            type: .executable
                        ),
                        TargetDescription(
                            name: "Plugin",
                            dependencies: [
                                "Generator"
                            ],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ],
                ),
                Manifest.createRemoteSourceControlManifest(
                    displayName: "swift-syntax",
                    url: "https://github.com/swiftlang/swift-syntax",
                    path: "/swift-syntax",
                    products: [
                        ProductDescription(
                            name: "SwiftSyntaxMacros",
                            type: .library(.automatic),
                            targets: ["SwiftSyntaxMacros"]
                        )
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntaxMacros")
                    ]
                )
            ],
            prebuilts: [prebuiltLibrary.identity: prebuiltLibrary.products.reduce(into: [:]) {
                $0[$1] = prebuiltLibrary
            }],
            observabilityScope: observability.topScope
        )

        let pifBuilder: PIFBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root, addLocalRpaths: true),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let pif = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host)
        )

        let targets = pif.workspace.projects.flatMap({ $0.underlying.targets })
        for target in targets {
            guard target.common.name != "Plugin" else {
                // The Plugin was already HOST_PLATFORM
                continue
            }
            let isHost: Bool = target.common.buildConfigs.contains {
                guard let platforms = $0.settings[.SUPPORTED_PLATFORMS] else {
                    return false
                }
                return platforms == ["$(HOST_PLATFORM)"]
            }
            #expect(isHost == false, "\(target.common.name)")
        }
    }
}
