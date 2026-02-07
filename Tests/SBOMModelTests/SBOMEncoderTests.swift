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
@testable import SBOMModel
import Testing

struct SBOMEncoderTests {
    private func verifyJSONFile(at path: AbsolutePath) throws {
        #expect(localFileSystem.exists(path), "File should exist at \(path)")

        let data = try localFileSystem.readFileContents(path)
        let jsonObject = try JSONSerialization.jsonObject(with: Data(data.contents))
        #expect(jsonObject is [String: Any], "File should contain valid JSON object")
    }

    @Test("writeSBOMs creates output directory if it doesn't exist")
    func writeSBOMsCreatesOutputDirectory() async throws {
        try await withTemporaryDirectory { tmpDir in
            let outputDir = tmpDir.appending("output")
            
            // Directory should not exist initially
            #expect(!localFileSystem.exists(outputDir), "Directory should not exist before test")

            let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
            let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: outputDir)

            #expect(localFileSystem.exists(outputDir), "Output directory should be created")
            #expect(!outputs.isEmpty, "Output paths should not be empty")
        }
    }

    @Test("writeSBOMs generates files for multiple specs")
    func writeSBOMsGeneratesFilesForMultipleSpecs() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
            let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: tmpDir)
            
            try #require(!outputs.isEmpty, "Output paths should not be empty")
            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 2, "Should generate two files for two specs")

            // Since test packages don't have real Git repos, the revision will be "unknown"
            // Filenames include timestamps, so we need to check for patterns
            let cycloneDXPattern = "cyclonedx1-1.7-MyApp-unknown-all-"
            let spdxPattern = "spdx3-3.0.1-MyApp-unknown-all-"

            let cycloneDXFile = try #require(
                files.first { $0.hasPrefix(cycloneDXPattern) && $0.hasSuffix(".json") },
                "Should generate CycloneDX file",
            )
            let spdxFile = try #require(
                files.first { $0.hasPrefix(spdxPattern) && $0.hasSuffix(".json") },
                "Should generate SPDX file",
            )

            try self.verifyJSONFile(at: tmpDir.appending(component: cycloneDXFile))
            try self.verifyJSONFile(at: tmpDir.appending(component: spdxFile))
        }
    }

    @Test("writeSBOMs with duplicate specs generates single file")
    func writeSBOMsWithDuplicateSpecsGeneratesSingleFile() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
            let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx, .cyclonedx1], outputDir: tmpDir)

            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 1, "Duplicate specs should result in single file")
            #expect(!outputs.isEmpty, "Output paths should not be empty")
        }
    }

    @Test("writeSBOMs tests cleans up properly on success")
    func writeSBOMsCleansUpProperlyOnSuccess() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
            let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: tmpDir)

            #expect(localFileSystem.exists(tmpDir), "Directory should exist after write")
            #expect(!outputs.isEmpty, "Output paths should not be empty")
            // Directory cleanup is handled automatically by withTemporaryDirectory
        }
    }

    @Test("writeSBOMs generates correct filename format")
    func writeSBOMsGeneratesCorrectFilenameFormat() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
            let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: tmpDir)

            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 1)

            let filename = files[0]
            // Format: {spec.type}-{spec.version}-{name}-{version}.json
            let components = filename.replacingOccurrences(of: ".json", with: "").split(separator: "-")
            #expect(components.count >= 4, "Filename should have at least 4 components")
            #expect(components[0] == "cyclonedx1", "First component should be spec type")
            #expect(components[1] == "1.7", "Second component should be spec version")
            #expect(components[2] == "swiftly", "Third component should be package name")
            #expect(!outputs.isEmpty, "Output paths should not be empty")
        }
    }

    @Test("encodeSBOM with outputDir writes file")
    func encodeSBOMWithOutputDirWritesFile() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
            let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)
            let spec = SBOMSpec(spec: .cyclonedx1)

            let _ = try await encoder.encodeSBOM(spec: spec, outputDir: tmpDir)

            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 1, "Should write exactly one file")
        }
    }

    @Test("writeSBOMs integration test with SPM graph")
    func writeSBOMsIntegrationTestWithSPMGraph() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
            let store = try SBOMTestStore.createSPMResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let _ = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: tmpDir)

            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 2, "Should generate both CycloneDX and SPDX files")

            // Verify both files are valid
            for filename in files {
                let filePath = tmpDir.appending(component: filename)
                try self.verifyJSONFile(at: filePath)
            }
        }
    }

    @Test("writeSBOMs integration test with Swiftly graph")
    func writeSBOMsIntegrationTestWithSwiftlyGraph() async throws {
        try await withTemporaryDirectory { tmpDir in
            let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
            let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
            let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
            let sbom = try await extractor.extractSBOM()
            let encoder = SBOMEncoder(sbom: sbom, observabilityScope: ObservabilitySystem.makeForTesting().topScope)

            let _ = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: tmpDir)

            let files = try localFileSystem.getDirectoryContents(tmpDir)
            #expect(files.count == 2, "Should generate both CycloneDX and SPDX files")

            // Verify both files are valid
            for filename in files {
                let filePath = tmpDir.appending(component: filename)
                try self.verifyJSONFile(at: filePath)
            }
        }
    }
}
