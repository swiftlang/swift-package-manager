//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Build
import PackageGraph
import PackageModel
import SourceKitLSPAPI
import SPMTestSupport
import TSCBasic
import XCTest

class SourceKitLSPAPITests: XCTestCase {
    func testBasicSwiftPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            productsBuildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            toolsBuildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        try description.checkArguments(for: "exe", graph: graph, partialArguments: ["/fake/path/to/swiftc", "-module-name", "exe", "-emit-dependencies", "-emit-module", "-emit-module-path", "/path/to/build/debug/exe.build/exe.swiftmodule"])
        try description.checkArguments(for: "lib", graph: graph, partialArguments: ["/fake/path/to/swiftc", "-module-name", "lib", "-emit-dependencies", "-emit-module", "-emit-module-path", "/path/to/build/debug/lib.swiftmodule"])
    }
}

extension SourceKitLSPAPI.BuildDescription {
    @discardableResult func checkArguments(for targetName: String, graph: PackageGraph, partialArguments: [String]) throws -> Bool {
        let target = try XCTUnwrap(graph.allTargets.first(where: { $0.name == targetName }))
        let buildTarget = try XCTUnwrap(self.getBuildTarget(for: target))

        guard let file = buildTarget.sources.first else {
            XCTFail("build target \(targetName) contains no files")
            return false
        }

        let arguments = try buildTarget.compileArguments(for: file)
        let result = arguments.firstIndex(of: partialArguments) != nil

        XCTAssertTrue(result, "could not match \(partialArguments) to actual arguments \(arguments)")
        return result
    }
}

// Since 'contains' is only available in macOS SDKs 13.0 or newer, we need our own little implementation.
extension RandomAccessCollection where Element: Equatable {
    fileprivate func firstIndex(of pattern: some RandomAccessCollection<Element>) -> Index? {
        guard !pattern.isEmpty && count >= pattern.count else {
            return nil
        }

        var i = startIndex
        for _ in 0..<(count - pattern.count + 1) {
            if self[i...].starts(with: pattern) {
                return i
            }
            i = self.index(after: i)
        }
        return nil
    }
}
