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

import XCTest
import Basics
import PackageLoading
import _InternalBuildTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

@_spi(SwiftPMInternal)
@testable import PackageModel

class PrebuiltsBuildPlanTests: XCTestCase {
    func testPrebuiltsFlags() async throws {
        // Make sure the include path for the prebuilts get passed to the
        // generated test entry point and discover targets on Linux/Windows
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
                "_SwiftLibraryPluginProvider"
            ],
            cModules: ["_SwiftSyntaxCShims"]
        )

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPackage/Sources/MyMacroMacros/MyMacroMacros.swift",
                "/MyPackage/Sources/MyMacros/MyMacros.swift",
                "/MyPackage/Sources/MyMacroTests/MyMacroTests.swift"
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    targets: [
                        TargetDescription(
                            name: "MyMacroMacros",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                            ],
                            type: .macro),
                        TargetDescription(
                            name: "MyMacros",
                            dependencies: [
                                "MyMacroMacros",
                            ]
                        ),
                        TargetDescription(
                            name: "MyMacroTests",
                            dependencies: [
                                "MyMacroMacros",
                                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                            ],
                            type: .test
                        )
                    ]
                )
            ],
            prebuilts: [prebuiltLibrary.identity: prebuiltLibrary.products.reduce(into: [:]) {
                $0[$1] = prebuiltLibrary
            }],
            observabilityScope: observability.topScope
        )

        func checkTriple(triple: Basics.Triple) async throws {
            let result = try await BuildPlanResult(
                plan: mockBuildPlan(
                    triple: triple,
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )
            )

#if os(Windows)
            let modulesDir = "\(prebuiltLibrary.path.pathString)\\Modules"
#else
            let modulesDir = "\(prebuiltLibrary.path.pathString)/Modules"
#endif
            let mytest = try XCTUnwrap(result.allTargets(named: "MyMacroTests").first)
            XCTAssert(try mytest.swift().compileArguments().contains(modulesDir))
            let entryPoint = try XCTUnwrap(result.allTargets(named: "MyPackagePackageTests").first)
            XCTAssert(try entryPoint.swift().compileArguments().contains(modulesDir))
            let discovery = try XCTUnwrap(result.allTargets(named: "MyPackagePackageDiscoveredTests").first)
            XCTAssert(try discovery.swift().compileArguments().contains(modulesDir))
        }

        try await checkTriple(triple: .x86_64Linux)
        try await checkTriple(triple: .x86_64Windows)
    }

    func testPrebuiltsWithIncludePath() async throws {
        // Make sure the include path for the prebuilts get passed to the
        // generated test entry point and discover targets on Linux/Windows
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
                "_SwiftLibraryPluginProvider"
            ],
            includePath: [
                "Sources/_SwiftSyntaxCShims/include"
            ]
        )

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPackage/Sources/MyMacroLibrary/MyMacroLibrary.swift",
                "/MyPackage/Sources/MyMacroMacros/MyMacroMacros.swift",
                "/MyPackage/Sources/MyMacros/MyMacros.swift",
                "/MyPackage/Sources/MyMacroTests/MyMacroTests.swift"
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    targets: [
                        TargetDescription(
                            name: "MyMacroLibrary",
                            dependencies: [
                                .product(name: "SwiftSyntax", package: "swift-syntax"),
                            ]
                        ),
                        TargetDescription(
                            name: "MyMacroMacros",
                            dependencies: [
                                "MyMacroLibrary",
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                            ],
                            type: .macro,
                        ),
                        TargetDescription(
                            name: "MyMacros",
                            dependencies: [
                                "MyMacroMacros",
                            ]
                        ),
                        TargetDescription(
                            name: "MyMacroTests",
                            dependencies: [
                                "MyMacroMacros",
                                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                            ],
                            type: .test
                        )
                    ]
                )
            ],
            prebuilts: [prebuiltLibrary.identity: prebuiltLibrary.products.reduce(into: [:]) {
                $0[$1] = prebuiltLibrary
            }],
            observabilityScope: observability.topScope
        )

        func checkTriple(triple: Basics.Triple) async throws {
            let result = try await BuildPlanResult(
                plan: mockBuildPlan(
                    triple: triple,
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )
            )

            let modulesDir = prebuiltLibrary.path.appending(component: "Modules").pathString
            let checkoutPath = try XCTUnwrap(prebuiltLibrary.checkoutPath)
            let includeDir = try XCTUnwrap(prebuiltLibrary.includePath)[0]
            let includePath = checkoutPath.appending(includeDir).pathString

            let mytest = try XCTUnwrap(result.allTargets(named: "MyMacroTests").first)
            XCTAssert(try mytest.swift().compileArguments().contains(modulesDir))
            let entryPoint = try XCTUnwrap(result.allTargets(named: "MyPackagePackageTests").first)
            XCTAssert(try entryPoint.swift().compileArguments().contains(modulesDir))
            let discovery = try XCTUnwrap(result.allTargets(named: "MyPackagePackageDiscoveredTests").first)
            XCTAssert(try discovery.swift().compileArguments().contains(modulesDir))

            let mymacro = try XCTUnwrap(result.allTargets(named: "MyMacroMacros").first)
            XCTAssert(try mymacro.swift().compileArguments().contains(modulesDir))
            XCTAssert(try mymacro.swift().compileArguments().contains(includePath))
        }

        try await checkTriple(triple: .x86_64Linux)
        try await checkTriple(triple: .x86_64Windows)
    }
}
