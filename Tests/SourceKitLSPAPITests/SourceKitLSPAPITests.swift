//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Build

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

import PackageModel
import SourceKitLSPAPI
import _InternalTestSupport
import XCTest

final class SourceKitLSPAPITests: XCTestCase {
    func testBasicSwiftPackage() async throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Plugins/plugin/plugin.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "plugin", type: .plugin, pluginCapability: .buildTool)
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        try description.checkArguments(
            for: "exe",
            graph: graph,
            partialArguments: [
                "-module-name", "exe",
                "-emit-dependencies",
                "-emit-module",
                "-emit-module-path", "/path/to/build/\(plan.destinationBuildParameters.triple)/debug/exe.build/exe.swiftmodule"
            ],
            isPartOfRootPackage: true
        )
        try description.checkArguments(
            for: "lib",
            graph: graph,
            partialArguments: [
                "-module-name", "lib",
                "-emit-dependencies",
                "-emit-module",
                "-emit-module-path", "/path/to/build/\(plan.destinationBuildParameters.triple)/debug/Modules/lib.swiftmodule"
            ],
            isPartOfRootPackage: true
        )
        try description.checkArguments(
            for: "plugin",
            graph: graph,
            partialArguments: [
                "-I", "/fake/manifestLib/path"
            ],
            isPartOfRootPackage: true,
            destination: .tools
        )
    }

    func testModuleTraversal() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Plugins/plugin/plugin.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(
                            name: "plugin",
                            dependencies: ["exe"],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        struct Result {
            let parent: (any BuildTarget)?
            let module: any BuildTarget
            let depth: Int
        }

        var results: [Result] = []
        description.traverseModules { current, parent, depth in
            results.append(Result(parent: parent, module: current, depth: depth))
        }

        XCTAssertEqual(results.count, 6)

        // "lib" is the most interesting here because it appears on multiple depths due to
        // "exe" being a dependency of the "plugin".
        XCTAssertEqual(results.filter { $0.module.name == "lib" }.reduce(into: Set<Int>()) {
            $0.insert($1.depth)
        }.sorted(), [1, 2, 3])
    }
}

extension SourceKitLSPAPI.BuildDescription {
    @discardableResult func checkArguments(
        for targetName: String,
        graph: ModulesGraph,
        partialArguments: [String],
        isPartOfRootPackage: Bool,
        destination: BuildTriple = .destination
    ) throws -> Bool {
        let target = try XCTUnwrap(graph.module(for: targetName, destination: destination))
        let buildTarget = try XCTUnwrap(self.getBuildTarget(for: target, in: graph))

        guard let file = buildTarget.sources.first else {
            XCTFail("build target \(targetName) contains no files")
            return false
        }

        let arguments = try buildTarget.compileArguments(for: file)
        let result = arguments.contains(partialArguments)

        XCTAssertTrue(result, "could not match \(partialArguments) to actual arguments \(arguments)")
        XCTAssertEqual(buildTarget.isPartOfRootPackage, isPartOfRootPackage)
        return result
    }
}
