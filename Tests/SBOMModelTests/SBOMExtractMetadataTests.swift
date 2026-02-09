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

import Foundation
@testable import SBOMModel
import Testing

@Suite(
    .tags(
        .Feature.SBOM
    )
)
struct SBOMExtractMetadataTests {
    @Test("extractMetadata good weather")
    func extractMetadataParameterized() async throws {
        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let metadata = try await extractor.extractMetadata()

        let timestamp = try #require(metadata.timestamp)
        #expect(!timestamp.isEmpty)

        let formatter = ISO8601DateFormatter()
        _ = try #require(formatter.date(from: timestamp))

        let creators = try #require(metadata.creators)
        #expect(creators.count == 1)
        let creator = creators[0]
        #expect(!creator.id.value.isEmpty)
        #expect(creator.name == "swift-package-manager")
        #expect(!creator.version.isEmpty)

        let licenses = try #require(creator.licenses)
        #expect(licenses.count == 1)
        let license = licenses[0]
        #expect(license.name == "Apache-2.0")
        #expect(license.url == "http://swift.org/LICENSE.txt")
    }
}
