//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Testing

import Basics
@testable import Build
import LLBuildManifest
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph

struct WindowsBuildPlanTests {
    // Tests that our build plan is build correctly to handle separation
    // of object files that export symbols and ones that don't and to ensure
    // DLL products pick up the right ones.

    @Test(
        arguments: [
            (triple: Triple.x86_64Windows, label: "x86_64-unknown-windows-msvc"),
            (triple: Triple.x86_64MacOS, label: "x86_64-apple-macosx"),
            (triple: Triple.x86_64Linux, label: "x86_64-unknown-linux-gnu"),
        ]
    )
    func validateTriple(triple: Triple, label: String) async throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/libPkg/Sources/coreLib/coreLib.swift",
            "/libPkg/Sources/dllLib/dllLib.swift",
            "/libPkg/Sources/staticLib/staticLib.swift",
            "/libPkg/Sources/objectLib/objectLib.swift",
            "/exePkg/Sources/exe/main.swift",
        ])

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createFileSystemManifest(
                    displayName: "libPkg",
                    path: "/libPkg",
                    products: [
                        .init(name: "DLLProduct", type: .library(.dynamic), targets: ["dllLib"]),
                        .init(name: "StaticProduct", type: .library(.static), targets: ["staticLib"]),
                        .init(name: "ObjectProduct", type: .library(.automatic), targets: ["objectLib"]),
                    ],
                    targets: [
                        .init(name: "coreLib", dependencies: []),
                        .init(name: "dllLib", dependencies: ["coreLib"]),
                        .init(name: "staticLib", dependencies: ["coreLib"]),
                        .init(name: "objectLib", dependencies: ["coreLib"]),
                    ]
                ),
                .createRootManifest(
                    displayName: "exePkg",
                    path: "/exePkg",
                    dependencies: [.fileSystem(path: "/libPkg")],
                    targets: [
                        .init(
                            name: "exe",
                            dependencies: [
                                .product(name: "DLLProduct", package: "libPkg"),
                                .product(name: "StaticProduct", package: "libPkg"),
                                .product(name: "ObjectProduct", package: "libPkg"),
                            ]
                        )
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                triple: triple
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                triple: triple
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let llbuild = LLBuildManifestBuilder(
            plan,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        try llbuild.generateManifest(at: "/manifest")
        let commands = llbuild.manifest.commands

        func hasStatic(_ name: String) throws -> Bool {
            let tool = try #require(commands[name]?.tool as? SwiftCompilerTool)
            return tool.otherArguments.contains("-static")
        }

        #expect(try hasStatic("C.coreLib-\(label)-debug.module") == triple.isWindows(), "\(label)")
        #expect(try hasStatic("C.dllLib-\(label)-debug.module") == false, "\(label)")
        #expect(try hasStatic("C.staticLib-\(label)-debug.module") == triple.isWindows(), "\(label)")
        #expect(try hasStatic("C.objectLib-\(label)-debug.module") == triple.isWindows(), "\(label)")
        #expect(try hasStatic("C.exe-\(label)-debug.module") == triple.isWindows(), "\(label)")
    }
}
