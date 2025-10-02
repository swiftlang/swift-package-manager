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

import PackageGraph

import _InternalTestSupport
import SPMBuildCore

struct BuildPlanTraversalTests {
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

    @Test
    func trivialTraversal() async throws {
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

        #expect(self.getParents(in: results, for: "app") == [])
        #expect(self.getParents(in: results, for: "lib") == ["app", "test"])
        #expect(self.getParents(in: results, for: "test") == [])
    }

    @Test
    func traversalWithDifferentDestinations() async throws {
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

        #expect(self.getParents(in: results, for: "MMIO") == ["HAL"])
        #expect(self.getParents(in: results, for: "SwiftSyntax", destination: .host) == ["MMIOMacros"])
        #expect(self.getParents(in: results, for: "HAL", destination: .target) == ["Core", "HALTests"])
        #expect(self.getParents(in: results, for: "HAL", destination: .host) == [])
    }

    @Test
    func traversalWithTestThatDependsOnMacro() async throws {
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

        // Tests that if one of the test targets directly depends
        // on a macro - all tests are built for the "host".
        var results: [Result] = []
        plan.traverseModules {
            results.append(Result(parent: $1, module: $0))
        }

        let package = try #require(graph.package(for: "swift-mmio"))

        // Tests that if one of the test targets directly depends
        // on a macro - all tests are built for the "host".
        for module in package.modules where module.type == .test {
            let results = getResults(for: module.name, in: results)
            #expect(results.allSatisfy { $0.module.1 == .host })
        }
    }

    @Test
    func recursiveDependencyTraversal() async throws {
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

        let mmioModule = try #require(plan.description(for: graph.module(for: "MMIO")!, context: .target))

        var moduleDependencies: [(ResolvedModule, Dest, Build.ModuleBuildDescription?)] = []
        plan.traverseDependencies(of: mmioModule) { product, destination, description in
            #expect(product.name == "SwiftSyntax")
            #expect(destination == .host)
            #expect(description == nil)
        } onModule: { module, destination, description in
            moduleDependencies.append((module, destination, description))
        }

        #expect(moduleDependencies.count == 2)

        // The ordering is guaranteed by the traversal

        #expect(moduleDependencies[0].0.name == "MMIOMacros")
        #expect(moduleDependencies[1].0.name == "SwiftSyntax")

        for index in 0 ..< moduleDependencies.count {
            #expect(moduleDependencies[index].1 == .host)
            #expect(moduleDependencies[index].2 != nil)
        }

        let directDependencies = mmioModule.dependencies(using: plan)

        #expect(directDependencies.count == 1)

        let dependency = try #require(directDependencies.first)
        if case .module(let module, let description) = dependency {
            #expect(module.name == "MMIOMacros")
            let desc = try #require(description)
            #expect(desc.destination == .host)
        } else {
            Issue.record("Expected MMIOMacros module")
        }

        let dependencies = mmioModule.recursiveDependencies(using: plan)

        #expect(dependencies.count == 3)

        // MMIOMacros (module) -> SwiftSyntax (product) -> SwiftSyntax (module)

        if case .module(let module, let description) = dependencies[0] {
            #expect(module.name == "MMIOMacros")
            let desc = try #require(description)
            #expect(desc.destination == .host)
        } else {
            Issue.record("Expected MMIOMacros module")
        }

        if case .product(let product, let description) = dependencies[1] {
            #expect(product.name == "SwiftSyntax")
            #expect(description == nil)
        } else {
            Issue.record("Expected SwiftSyntax product")
        }

        if case .module(let module, let description) = dependencies[2] {
            #expect(module.name == "SwiftSyntax")
            let desc = try #require(description)
            #expect(desc.destination == .host)
        } else {
            Issue.record("Expected SwiftSyntax module")
        }
    }

    @Test
    func recursiveDependencyTraversalWithDuplicates() async throws {
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

        let testModule = try #require(plan.description(for: graph.module(for: "MMIOMacrosTests")!, context: .host))

        let dependencies = testModule.recursiveDependencies(using: plan)
        #expect(dependencies.count == 9)

        struct ModuleResult: Hashable {
            let module: ResolvedModule
            let destination: Dest
        }

        var uniqueModules = Set<ModuleResult>()
        for dependency in dependencies {
            if case .module(let module, let description) = dependency {
                #expect(description != nil)
                #expect(description!.destination == .host)
                #expect(uniqueModules.insert(.init(module: module, destination: description!.destination))
                    .inserted)
            }
        }
    }
}
