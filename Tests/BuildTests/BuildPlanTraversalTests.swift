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
            results.append(Result(parent: $1, module: $0))
        }

        XCTAssertEqual(self.getParents(in: results, for: "app"), [])
        XCTAssertEqual(self.getParents(in: results, for: "lib"), ["app", "test"])
        XCTAssertEqual(self.getParents(in: results, for: "test"), [])
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
            results.append(Result(parent: $1, module: $0))
        }

        XCTAssertEqual(self.getParents(in: results, for: "MMIO"), ["HAL"])
        XCTAssertEqual(self.getParents(in: results, for: "SwiftSyntax", destination: .host), ["MMIOMacros"])
        XCTAssertEqual(self.getParents(in: results, for: "HAL", destination: .target), ["Core", "HALTests"])
        XCTAssertEqual(self.getParents(in: results, for: "HAL", destination: .host), [])
    }

    func testRecursiveDependencyTraversal() async throws {
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

        let mmioModule = try XCTUnwrap(plan.description(for: graph.module(for: "MMIO")!, context: .target))

        var moduleDependencies: [(ResolvedModule, Dest, Build.ModuleBuildDescription?)] = []
        plan.traverseDependencies(of: mmioModule) { product, destination, description in
            XCTAssertEqual(product.name, "SwiftSyntax")
            XCTAssertEqual(destination, .host)
            XCTAssertNil(description)
            return .continue
        } onModule: { module, destination, description in
            moduleDependencies.append((module, destination, description))
            return .continue
        }

        XCTAssertEqual(moduleDependencies.count, 2)

        // The ordering is guaranteed by the traversal

        XCTAssertEqual(moduleDependencies[0].0.name, "MMIOMacros")
        XCTAssertEqual(moduleDependencies[1].0.name, "SwiftSyntax")

        for index in 0 ..< moduleDependencies.count {
            XCTAssertEqual(moduleDependencies[index].1, .host)
            XCTAssertNotNil(moduleDependencies[index].2)
        }

        let directDependencies = mmioModule.dependencies(using: plan)

        XCTAssertEqual(directDependencies.count, 1)

        let dependency = try XCTUnwrap(directDependencies.first)
        if case .module(let module, let description) = dependency {
            XCTAssertEqual(module.name, "MMIOMacros")
            try XCTAssertEqual(XCTUnwrap(description).destination, .host)
        } else {
            XCTFail("Expected MMIOMacros module")
        }

        let dependencies = mmioModule.recursiveDependencies(using: plan)

        XCTAssertEqual(dependencies.count, 3)

        // MMIOMacros (module) -> SwiftSyntax (product) -> SwiftSyntax (module)

        if case .module(let module, let description) = dependencies[0] {
            XCTAssertEqual(module.name, "MMIOMacros")
            try XCTAssertEqual(XCTUnwrap(description).destination, .host)
        } else {
            XCTFail("Expected MMIOMacros module")
        }

        if case .product(let product, let description) = dependencies[1] {
            XCTAssertEqual(product.name, "SwiftSyntax")
            XCTAssertNil(description)
        } else {
            XCTFail("Expected SwiftSyntax product")
        }

        if case .module(let module, let description) = dependencies[2] {
            XCTAssertEqual(module.name, "SwiftSyntax")
            try XCTAssertEqual(XCTUnwrap(description).destination, .host)
        } else {
            XCTFail("Expected SwiftSyntax module")
        }
    }

    func testRecursiveDependencyTraversalWithDuplicates() async throws {
        let destinationTriple = Triple.arm64Linux
        let toolsTriple = Triple.x86_64MacOS

        let (graph, fs, scope) = try macrosTestsPackageGraph()
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

        let testModule = try XCTUnwrap(plan.description(for: graph.module(for: "MMIOMacrosTests")!, context: .host))

        let dependencies = testModule.recursiveDependencies(using: plan)
        XCTAssertEqual(dependencies.count, 9)

        struct ModuleResult: Hashable {
            let module: ResolvedModule
            let destination: Dest
        }

        var uniqueModules = Set<ModuleResult>()
        for dependency in dependencies {
            if case .module(let module, let description) = dependency {
                XCTAssertNotNil(description)
                XCTAssertEqual(description!.destination, .host)
                XCTAssertTrue(
                    uniqueModules.insert(.init(module: module, destination: description!.destination))
                        .inserted
                )
            }
        }
    }
}
