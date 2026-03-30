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
import Testing

struct SBOMTestTraits {
    
    private func extractSBOM(from graph: ModulesGraph) async throws -> SBOMDependencies {
        // doesn't matter which store is used, so just the simple one
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(
            modulesGraph: graph,
            dependencyGraph: nil,
            store: store
        )
        return try await extractor.extractDependencies()
    }
    
    // MARK: - Tests
    
    @Test("SBOM extraction with PackageConditionalDeps fixture - default traits")
    func extractSBOMwithConditionalDepsFixtureDefaultTraits() async throws {
        let graph = try await SBOMTestModulesGraph.createConditionalModulesGraph(
            traitConfiguration: .default
        )
        let dependencies = try await extractSBOM(from: graph)
        
        // Verify: Package1 should be included (default trait enables it)
        #expect(dependencies.components.contains(where: { $0.name == "package1" }))
        
        // Verify: Package2 should NOT be included (trait not enabled by default)
        #expect(!dependencies.components.contains(where: { $0.name == "package2" }))
        
        // Verify: Root package is included
        #expect(dependencies.components.contains(where: { $0.name == "packageconditionaldeps" }))
    }
    
    @Test("SBOM extraction with PackageConditionalDeps fixture - all traits enabled")
    func extractSBOMwithConditionalDepsFixtureAllTraits() async throws {
        let graph = try await SBOMTestModulesGraph.createConditionalModulesGraph(
            traitConfiguration: .enabledTraits(["EnablePackage1Dep", "EnablePackage2Dep"])
        )
        let dependencies = try await extractSBOM(from: graph)
        
        // Verify: Both packages should be included (both traits enabled)
        #expect(dependencies.components.contains(where: { $0.name == "package1" }))
        #expect(dependencies.components.contains(where: { $0.name == "package2" }))
        #expect(dependencies.components.contains(where: { $0.name == "packageconditionaldeps" }))
    }
    
    @Test("SBOM extraction with PackageConditionalDeps fixture - no traits enabled")
    func extractSBOMwithConditionalDepsFixtureNoTraits() async throws {
        let graph = try await SBOMTestModulesGraph.createConditionalModulesGraph(
            traitConfiguration: .disableAllTraits
        )
        let dependencies = try await extractSBOM(from: graph)
        
        // Verify: Neither dependency package should be included (no traits enabled)
        #expect(!dependencies.components.contains(where: { $0.name == "package1" }))
        #expect(!dependencies.components.contains(where: { $0.name == "package2" }))
        
        // Verify: Root package is still included
        #expect(dependencies.components.contains(where: { $0.name == "packageconditionaldeps" }))
    }
}