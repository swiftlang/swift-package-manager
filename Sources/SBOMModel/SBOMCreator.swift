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

package struct SBOMCreator {
    package let input: SBOMInput
    
    package init(input: SBOMInput) {
        self.input = input
    }

    package static func resolveSBOMDirectory(from configPath: AbsolutePath?, withDefault defaultPath: AbsolutePath) async -> AbsolutePath {
        return configPath ?? defaultPath.appending(component: "sboms")
    }

    package func createSBOMs() async throws -> [AbsolutePath] {
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
        let outputPaths = try await encoder.writeSBOMs(
            specs: input.specs,
            outputDir: input.dir,
            filter: input.filter
        )

        guard !outputPaths.isEmpty else {
            throw SBOMError.failedToWriteSBOM
        }

        return outputPaths
    }
}
