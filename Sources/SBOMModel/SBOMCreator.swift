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

import Basics
import Foundation

internal struct SBOMResult {
    internal let spec: SBOMSpec
    internal let path: AbsolutePath

    internal init(spec: SBOMSpec, path: AbsolutePath) {
        self.spec = spec
        self.path = path
    }
}

package struct SBOMCreator {

    package let input: SBOMInput
    
    package init(input: SBOMInput) {
        self.input = input
    }

    package static func resolveSBOMDirectory(from configPath: AbsolutePath?, withDefault defaultPath: AbsolutePath) async -> AbsolutePath {
        return configPath ?? defaultPath.appending(component: "sboms")
    }

    /// Creates SBOMs with timing and logging output to the observability scope.
    /// This method consolidates the common SBOM generation logic used by both
    /// the `swift build` and `swift package generate-sbom` commands.
    ///
    /// - Returns: An array of paths to the created SBOM files
    /// - Throws: SBOMError if SBOM creation fails
    package func createSBOMsWithLogging() async throws {
        input.observabilityScope.print("Creating SBOMs...", verbose: true)
        let sbomStartTime = ContinuousClock.Instant.now
        
        let results = try await createSBOMs()
        
        let duration = ContinuousClock.Instant.now - sbomStartTime
        let formattedDuration = duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2, rounded: .up)))
        
        for result in results {
            input.observabilityScope.print("- created \(result.spec.concreteSpec) v\(SBOMVersionRegistry.getLatestVersion(for: result.spec)) SBOM at \(result.path.pathString)", verbose: true)
        }
        input.observabilityScope.print("SBOMs created  (\(formattedDuration))", verbose: true)
    }

    internal func createSBOMs() async throws -> [SBOMResult] {
        guard !input.specs.isEmpty else {
            throw SBOMError.noSpecsProvided
        }
        
        let extractor = SBOMExtractor(
            modulesGraph: input.modulesGraph,
            dependencyGraph: input.dependencyGraph,
            store: input.store
        )
        
        let sbom = try await extractor.extractSBOM(
            product: input.product,
            filter: input.filter
        )
        
        let encoder = SBOMEncoder(sbom: sbom, observabilityScope: input.observabilityScope)
        let results = try await encoder.writeSBOMs(
            specs: input.specs,
            outputDir: input.dir,
            filter: input.filter
        )

        guard !results.isEmpty else {
            throw SBOMError.failedToWriteSBOM
        }

        return results
    }
}
