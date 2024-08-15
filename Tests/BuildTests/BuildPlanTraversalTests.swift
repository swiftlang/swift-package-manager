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

import PackageGraph

import _InternalTestSupport
import SPMBuildCore

final class BuildPlanTraversalTests: XCTestCase {
    typealias Dest = BuildParameters.Destination

    struct Result {
        let parent: (ResolvedModule, Dest)?
        let module: (ResolvedModule, Dest)
        let depth: Int
    }

    func getResults(
        for module: String,
        with destination: Dest? = nil,
        in results: [Result]
    ) -> [Result] {
        results.filter { result in
            if result.module.0.name != module {
                return false
            }
            guard let destination else {
                return true
            }

            return result.module.1 == destination
        }
    }

    func getParents(
        in results: [Result],
        for module: String,
        destination: Dest? = nil
    ) -> [String] {
        self.getResults(
            for: module,
            with: destination,
            in: results
        ).reduce(into: Set<String>()) {
            if let parent = $1.parent {
                $0.insert(parent.0.name)
            }
        }.sorted()
    }

    func getUniqueOccurrences(
        in results: [Result],
        for module: String,
        destination: Dest? = nil
    ) -> [Int] {
        self.getResults(
            for: module,
            with: destination,
            in: results
        ).reduce(into: Set<Int>()) {
            $0.insert($1.depth)
        }.sorted()
    }

    func testTrivialTraversal() async throws {
        let destinationTriple = Triple.arm64Linux
        let toolsTriple = Triple.x86_64MacOS

        let (graph, fs, scope) = try trivialPackageGraph()
        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                triple: destinationTriple
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                triple: toolsTriple
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        var results: [Result] = []
        plan.traverseModules {
            results.append(Result(parent: $1, module: $0, depth: $2))
        }

        XCTAssertEqual(self.getParents(in: results, for: "app"), [])
        XCTAssertEqual(self.getParents(in: results, for: "lib"), ["app", "test"])
        XCTAssertEqual(self.getParents(in: results, for: "test"), [])

        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "app"), [1])
        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "lib"), [1, 2])
        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "test"), [1])
    }

    func testTraversalWithDifferentDestinations() async throws {
        let destinationTriple = Triple.arm64Linux
        let toolsTriple = Triple.x86_64MacOS

        let (graph, fs, scope) = try macrosPackageGraph()
        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                triple: destinationTriple
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                triple: toolsTriple
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: scope
        )

        var results: [Result] = []
        plan.traverseModules {
            results.append(Result(parent: $1, module: $0, depth: $2))
        }

        XCTAssertEqual(self.getParents(in: results, for: "MMIO"), ["HAL"])
        XCTAssertEqual(self.getParents(in: results, for: "SwiftSyntax", destination: .host), ["MMIOMacros"])
        XCTAssertEqual(self.getParents(in: results, for: "HAL", destination: .target), ["Core", "HALTests"])
        XCTAssertEqual(self.getParents(in: results, for: "HAL", destination: .host), [])

        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "MMIO"), [1, 2, 3, 4])
        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "SwiftSyntax", destination: .target), [1])
        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "SwiftSyntax", destination: .host), [2, 3, 4, 5, 6])
        XCTAssertEqual(self.getUniqueOccurrences(in: results, for: "HAL"), [1, 2, 3])
    }
}
