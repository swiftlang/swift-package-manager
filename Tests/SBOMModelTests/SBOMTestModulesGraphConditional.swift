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

import _InternalTestSupport
import Basics
import Foundation
import PackageGraph
import PackageModel
@testable import SBOMModel

extension SBOMTestModulesGraph {
    private static let conditionalDeps: [MockDependency] = [
        .sourceControl(path: "./Package1", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Package1Library1"])),
        .sourceControl(path: "./Package2", requirement: .upToNextMajor(from: "1.0.0"), products: .specific(["Package2Library1"]))
    ]

    static func createConditionalModulesGraph(traitConfiguration: TraitConfiguration) async throws -> ModulesGraph {
       let sandbox = AbsolutePath("/tmp/ws-traits-\(UUID().uuidString)")
        let fs = InMemoryFileSystem()
        
        let workspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "PackageConditionalDeps",
                    targets: [
                        try MockTarget(
                            name: "PackageConditionalDeps",
                            dependencies: [
                                .product(
                                    name: "Package1Library1",
                                    package: "Package1",
                                    condition: .init(traits: ["EnablePackage1Dep"])
                                ),
                                .product(
                                    name: "Package2Library1",
                                    package: "Package2",
                                    condition: .init(traits: ["EnablePackage2Dep"])
                                )
                            ]
                        )
                    ],
                    products: [
                        MockProduct(name: "PackageConditionalDeps", modules: ["PackageConditionalDeps"])
                    ],
                    dependencies: [
                        .sourceControl(path: "./Package1", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(path: "./Package2", requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    traits: [
                        .init(name: "default", enabledTraits: ["EnablePackage1Dep"]),
                        "EnablePackage1Dep",
                        "EnablePackage2Dep"
                    ]
                )
            ],
            packages: [
                MockPackage(
                    name: "Package1",
                    targets: [try MockTarget(name: "Package1Library1")],
                    products: [MockProduct(name: "Package1Library1", modules: ["Package1Library1"])],
                    traits: ["Package1Trait1"],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Package2",
                    targets: [try MockTarget(name: "Package2Library1")],
                    products: [MockProduct(name: "Package2Library1", modules: ["Package2Library1"])],
                    versions: ["1.0.0"]
                )
            ],
            traitConfiguration: traitConfiguration
        )
        
        var capturedGraph: ModulesGraph?
        try await workspace.checkPackageGraph(
            roots: ["PackageConditionalDeps"],
            deps: conditionalDeps
        ) { graph, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
            capturedGraph = graph
        }
        
        guard let graph = capturedGraph else {
            throw SBOMTestError.failedToCaptureModulesGraph
        }
        return graph
    }
}


