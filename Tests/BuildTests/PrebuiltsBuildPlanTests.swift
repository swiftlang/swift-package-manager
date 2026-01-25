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
import Build

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
                "/MyPackage/Sources/MyMacroTests/MyMacroTests.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacros/SwiftSyntaxMacros.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacrosTestSupport/SwiftSyntaxMacrosTestSupport.swift",
                "/swift-syntax/Sources/SwiftCompilerPlugin/SwiftCompilerPlugin.swift",
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    dependencies: [
                        .remoteSourceControl(url: "https://github.com/swiftlang/swift-syntax", requirement: .exact("600.0.1")),
                    ],
                    products: [
                        ProductDescription(
                            name: "MyMacros",
                            type: .library(.automatic),
                            targets: ["MyMacros"]
                        )
                    ],
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
                        ),
                        ProductDescription(
                            name: "SwiftSyntaxMacrosTestSupport",
                            type: .library(.automatic),
                            targets: ["SwiftSyntaxMacrosTestSupport"]
                        ),
                        ProductDescription(
                            name: "SwiftCompilerPlugin",
                            type: .library(.automatic),
                            targets: ["SwiftCompilerPlugin"]
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntaxMacros"),
                        TargetDescription(name: "SwiftSyntaxMacrosTestSupport"),
                        TargetDescription(name: "SwiftCompilerPlugin"),
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

    // Make sure the include path for the prebuilts get passed to the
    // generated test entry point and discover targets on Linux/Windows
    func testPrebuiltsWithIncludePath() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPackage/Sources/MyMacroLibrary/MyMacroLibrary.swift",
                "/MyPackage/Sources/MyMacroMacros/MyMacroMacros.swift",
                "/MyPackage/Sources/MyMacros/MyMacros.swift",
                "/MyPackage/Sources/MyMacroTests/MyMacroTests.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacros/SwiftSyntaxMacros.swift",
                "/swift-syntax/Sources/SwiftSyntaxMacrosTestSupport/SwiftSyntaxMacrosTestSupport.swift",
                "/swift-syntax/Sources/SwiftCompilerPlugin/SwiftCompilerPlugin.swift",
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "MyPackage",
                    path: "/MyPackage",
                    dependencies: [
                        .remoteSourceControl(url: "https://github.com/swiftlang/swift-syntax", requirement: .exact("600.0.1")),
                    ],
                    products: [
                        ProductDescription(
                            name: "MyMacros",
                            type: .library(.automatic),
                            targets: ["MyMacros"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "MyMacroLibrary",
                            dependencies: [
                                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
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
                        ),
                        ProductDescription(
                            name: "SwiftSyntaxMacrosTestSupport",
                            type: .library(.automatic),
                            targets: ["SwiftSyntaxMacrosTestSupport"]
                        ),
                        ProductDescription(
                            name: "SwiftCompilerPlugin",
                            type: .library(.automatic),
                            targets: ["SwiftCompilerPlugin"]
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntaxMacros"),
                        TargetDescription(name: "SwiftSyntaxMacrosTestSupport"),
                        TargetDescription(name: "SwiftCompilerPlugin"),
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

    // Make sure the prebuilt settings are imparted up the build graph to the executables.
    // Include skipping over a library that doesn't use prebuilts.
    func testIndirectLibrary() async throws {
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
                            targets: [
                                "MacroLib"
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

        let result = try await BuildPlanResult(
            plan: mockBuildPlan(
                triple: .arm64MacOS,
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
        )

        // Make sure everyone has the modules dir that needs it and those that don't don't
        let modulesDir = prebuiltLibrary.path.appending(component: "Modules").pathString
        let libDir = prebuiltLibrary.path.appending(component: "lib").pathString
        let lib = "-l\(prebuiltLibrary.libraryName)"

        let Base = try XCTUnwrap(result.targetMap.filter({ $0.module.name == "Base" }).only)
        XCTAssertEqual(Base.buildParameters.destination, .host)
        XCTAssert(try Base.swift().compileArguments().contains(modulesDir))

        let Intermediate = try XCTUnwrap(result.targetMap.filter({ $0.module.name == "Intermediate" }).only)
        XCTAssertEqual(Intermediate.buildParameters.destination, .host)
        XCTAssert(try Intermediate.swift().compileArguments().contains(modulesDir))

        let Macros = try XCTUnwrap(result.targetMap.filter({ $0.module.name == "Macros" }).only)
        XCTAssertEqual(Macros.buildParameters.destination, .host)
        XCTAssert(try Macros.swift().compileArguments().contains(modulesDir))

        let MacrosExe = try XCTUnwrap(result.productMap.filter({ $0.product.name == "Macros" }).only)
        XCTAssertEqual(MacrosExe.destination, .host)
        let MacrosExeLinkArgs = try MacrosExe.linkArguments()
        XCTAssert(MacrosExeLinkArgs.contains(libDir))
        XCTAssert(MacrosExeLinkArgs.contains(lib))

        // The MacroLib is target only
        let MacroLib = try XCTUnwrap(result.targetMap.filter({ $0.module.name == "MacroLib" }).only)
        XCTAssertEqual(MacroLib.buildParameters.destination, .target)
        XCTAssert(try !MacroLib.swift().compileArguments().contains(modulesDir))
    }

    // Test that a prebuilt leaking out the root package's products disables them all
    func testIndirectLibraryLeak() async throws {
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

        let result = try await BuildPlanResult(
            plan: mockBuildPlan(
                triple: .arm64MacOS,
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
        )

        // Make sure nothing is using the prebuilts
        let modulesDir = prebuiltLibrary.path.appending(component: "Modules").pathString
        let libDir = prebuiltLibrary.path.appending(component: "lib").pathString
        let lib = "-l\(prebuiltLibrary.libraryName)"

        for target in result.targetMap {
            XCTAssert(try !target.swift().compileArguments().contains(modulesDir))
        }

        for product in result.productMap {
            let linkArgs = try product.linkArguments()
            XCTAssert(!linkArgs.contains(libDir))
            XCTAssert(!linkArgs.contains(lib))
        }

        let prebuiltUsers = Set([
            "LeakyLib",
            "Base",
            "Macros"
        ])
        for target in result.targetMap where prebuiltUsers.contains(target.module.name) {
            XCTAssert(target.module.dependencies.contains(where: { $0.product?.packageIdentity == .plain("swift-syntax") }))
        }
    }
}
