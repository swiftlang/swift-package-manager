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

import XCTest

import Basics
@testable import Build
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

final class WindowsBuildPlanTests: XCTestCase {
    // Tests that our build plan is build correctly to handle separation
    // of object files that export symbols and ones that don't and to ensure
    // DLL products pick up the right ones.
    func testDynamicSymbolHandling() async throws {
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
                        .init(name: "exe", dependencies: [
                            .product(name: "DLLProduct", package: "libPkg"),
                            .product(name: "StaticProduct", package: "libPkg"),
                            .product(name: "ObjectProduct", package: "libPkg"),
                        ]),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        let plan = try await mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let result = try BuildPlanResult(plan: plan)
        let exe = try result.buildProduct(for: "exe")

        let llbuild = LLBuildManifestBuilder(
            plan,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        try llbuild.generateManifest(at: "/manifest")

        for command in llbuild.manifest.commands {
            print(command.key)
        }
    }
}
