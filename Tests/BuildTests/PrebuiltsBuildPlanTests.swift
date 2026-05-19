//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
import Basics
import PackageLoading
import _InternalBuildTestSupport
import Build

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

@_spi(SwiftPMInternal)
@testable import PackageModel

@Suite
struct PrebuiltsBuildPlanTests {
    @Test func prebuilts() async throws {
        guard let host = PackageModel.Platform.host else {
            return
        }

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

        // The prebuilts used for the rest of these tests
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
                "_SwiftLibraryPluginProvider"
            ],
            includePath: [
                "Sources/_SwiftSyntaxCShims/include"
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
                    ],
                    targets: [
                        TargetDescription(
                            name: "MyApp",
                            dependencies: [
                                .product(name: "MacroLib", package: "MyPackage"),
                                .product(name: "Base", package: "MyPackage"),
                            ],
                            type: .executable
                        ),
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
                            targets: [ "MacroLib" ]
                        ),
                        ProductDescription(
                            name: "Base",
                            type: .library(.automatic),
                            targets: ["Base"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "Base",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
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
                )
            ],
            prebuilts: [prebuiltLibrary.identity: [prebuiltLibrary]],
            observabilityScope: observability.topScope
        )

        func usesPrebuilts(target: ModuleBuildDescription, plan: BuildPlan) throws {
            #expect(!target.hasProductDependency(named: "SwiftSyntaxMacros", plan: plan))
            for path in prebuiltLibrary.headerPaths {
                #expect(try target.swift().compileArguments().contains(path.pathString))
            }
        }

        func noPrebuilts(target: ModuleBuildDescription, plan: BuildPlan) throws {
            #expect(target.hasProductDependency(named: "SwiftSyntaxMacros", plan: plan))
            for path in prebuiltLibrary.headerPaths {
                #expect(try !target.swift().compileArguments().contains(path.pathString))
            }
        }

        func usesPrebuilts(product: ProductBuildDescription, plan: BuildPlan) throws {
            #expect(try product.linkArguments().contains(prebuiltLibrary.libraryPath.pathString))
        }

        func noPrebuilts(product: ProductBuildDescription, plan: BuildPlan) throws {
            #expect(try !product.linkArguments().contains(prebuiltLibrary.libraryPath.pathString))
        }

        // Test host build
        do {
            let result = try await BuildPlanResult(
                plan: mockBuildPlan(
                    platform: host,
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )
            )

            let hostMacros = try #require(try result.target(named: "Macros", destination: .host))
            try usesPrebuilts(target: hostMacros, plan: result.plan)
            let hostBase = try #require(try result.target(named: "Base", destination: .host))
            try usesPrebuilts(target: hostBase, plan: result.plan)
            let targetBase = try #require(try result.target(named: "Base", destination: .target))
            try usesPrebuilts(target: targetBase, plan: result.plan)
            let targetMyApp = try #require(try result.target(named: "MyApp", destination: .target))
            try usesPrebuilts(target: targetMyApp, plan: result.plan)
            let productMyApp = try #require(try result.product(named: "MyApp", destination: .target))
            try usesPrebuilts(product: productMyApp, plan: result.plan)
        }

        // Test cross build
        do {
            let result = try await BuildPlanResult(
                plan: mockBuildPlan(
                    platform: .android,
                    useRealHostPlatform: true,
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )
            )

            let hostMacros = try #require(try result.target(named: "Macros", destination: .host))
            try usesPrebuilts(target: hostMacros, plan: result.plan)
            let hostBase = try #require(try result.target(named: "Base", destination: .host))
            try usesPrebuilts(target: hostBase, plan: result.plan)
            let targetBase = try #require(try result.target(named: "Base", destination: .target))
            try noPrebuilts(target: targetBase, plan: result.plan)
            let targetMyApp = try #require(try result.target(named: "MyApp", destination: .target))
            try noPrebuilts(target: targetMyApp, plan: result.plan)
            let productMyApp = try #require(try result.product(named: "MyApp", destination: .target))
            try noPrebuilts(product: productMyApp, plan: result.plan)
        }
    }
}

fileprivate extension ModuleBuildDescription {
    func hasProductDependency(named name: String, plan: BuildPlan) -> Bool {
        recursiveDependencies(using: plan).contains(where: {
            guard case let .product(product, _) = $0 else {
                return false
            }
            return product.name == name
        })
    }
}
