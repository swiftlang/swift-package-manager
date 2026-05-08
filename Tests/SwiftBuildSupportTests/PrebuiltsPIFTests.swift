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
import Foundation
import PackageLoading
import SPMBuildCore
import SwiftBuildSupport
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) @testable import PackageGraph
@_spi(SwiftPMInternal) @testable import PackageModel

/// PIF version of the PrebuiltsBuildPlanTests
@Suite
struct PrebuiltsPIFTests {
    @Test func testSuccessPath() async throws {
        let observability = ObservabilitySystem.makeForTesting()

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
                                .product(name: "MacroLib", package: "MyPackage"),
                                .product(name: "Base", package: "MyPackage"),
                            ],
                            type: .executable
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
                    ],
                    targets: [
                        TargetDescription(
                            name: "Base",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
                            ]
                        ),
                        TargetDescription(
                            name: "Macros",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                "Base",
                            ],
                            type: .macro
                        ),
                        TargetDescription(
                            name: "MacroLib",
                            dependencies: [
                                "Macros"
                            ]
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
            prebuilts: [prebuiltLibrary.identity: [prebuiltLibrary]],
            observabilityScope: observability.topScope
        )

        let pifBuilder: PIFBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root, addLocalRpaths: true),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild),
            hostBuildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let targetMap = pif.workspace.projects.flatMap(\.underlying.targets).reduce(into: [:]) { $0[$1.common.name] = $1 }

        let targetMacroSupport = try #require(targetMap["MacroSupport"])
        for config in targetMacroSupport.common.buildConfigs {
            let ldFlags = try #require(config.impartedBuildProperties.settings[.OTHER_LDFLAGS])
            #expect(ldFlags.contains(prebuiltLibrary.libraryPath.pathString))
            let swiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
            for headerPath in prebuiltLibrary.headerPaths {
                #expect(swiftFlags.contains(headerPath.pathString))
            }
            let cFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
            for headerPath in prebuiltLibrary.headerPaths {
                #expect(cFlags.contains(headerPath.pathString))
            }
        }
    }
}
