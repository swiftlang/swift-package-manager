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
    private func createTempOutputDir() throws -> AbsolutePath {
        let uniqueID = UUID().uuidString
        let tempDir = AbsolutePath("/tmp/SBOMEncoderTests-\(uniqueID)")
        try localFileSystem.createDirectory(tempDir, recursive: true)
        return tempDir
    }

    private func cleanupTempDir(_ path: AbsolutePath) throws {
        if localFileSystem.exists(path) {
            try localFileSystem.removeFileTree(path)
        }
    }

    private func verifyJSONFile(at path: AbsolutePath) throws {
        #expect(localFileSystem.exists(path), "File should exist at \(path)")

        let data = try localFileSystem.readFileContents(path)
        let jsonObject = try JSONSerialization.jsonObject(with: Data(data.contents))
        #expect(jsonObject is [String: Any], "File should contain valid JSON object")
    }

    @Test("writeSBOMs creates output directory if it doesn't exist")
    func writeSBOMsCreatesOutputDirectory() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        // Remove the directory to test creation
        try localFileSystem.removeFileTree(outputDir)
        #expect(!localFileSystem.exists(outputDir), "Directory should not exist before test")

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: outputDir)

        #expect(localFileSystem.exists(outputDir), "Output directory should be created")
        #expect(!outputs.isEmpty, "Output paths should not be empty")
    }

    @Test("writeSBOMs generates files for multiple specs")
    func writeSBOMsGeneratesFilesForMultipleSpecs() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
        #expect(files.count == 2, "Should generate two files for two specs")

        // Since test packages don't have real Git repos, the revision will be "unknown"
        // Filenames include timestamps, so we need to check for patterns
        let cycloneDXPattern = "cyclonedx1-1.7-MyApp-unknown-all-"
        let spdxPattern = "spdx3-3.0.1-MyApp-unknown-all-"

        let cycloneDXFile = files.first { $0.hasPrefix(cycloneDXPattern) && $0.hasSuffix(".json") }
        let spdxFile = files.first { $0.hasPrefix(spdxPattern) && $0.hasSuffix(".json") }

        #expect(cycloneDXFile != nil, "Should generate CycloneDX file")
        #expect(spdxFile != nil, "Should generate SPDX file")
        #expect(!outputs.isEmpty, "Output paths should not be empty")

        try self.verifyJSONFile(at: outputDir.appending(component: cycloneDXFile!))
        try self.verifyJSONFile(at: outputDir.appending(component: spdxFile!))
    }

    @Test("writeSBOMs with duplicate specs generates single file")
    func writeSBOMsWithDuplicateSpecsGeneratesSingleFile() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx, .cyclonedx1], outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
        #expect(files.count == 1, "Duplicate specs should result in single file")
        #expect(!outputs.isEmpty, "Output paths should not be empty")
    }

    @Test("writeSBOMs tests cleans up properly on success")
    func writeSBOMsCleansUpProperlyOnSuccess() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: outputDir)

        #expect(localFileSystem.exists(outputDir), "Directory should exist after write")

        // Cleanup
        try self.cleanupTempDir(outputDir)
        #expect(!localFileSystem.exists(outputDir), "Directory should be removed after cleanup")
        #expect(!outputs.isEmpty, "Output paths should not be empty")
    }

    @Test("writeSBOMs generates correct filename format")
    func writeSBOMsGeneratesCorrectFilenameFormat() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let outputs = try await encoder.writeSBOMs(specs: [.cyclonedx], outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
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

    @Test("encodeSBOM with outputDir writes file")
    func encodeSBOMWithOutputDirWritesFile() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSimpleModulesGraph()
        let store = try SBOMTestStore.createSimpleResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)
        let spec = SBOMSpec(type: .cyclonedx1, version: "1.7")

        let _ = try await encoder.encodeSBOM(spec: spec, outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
        #expect(files.count == 1, "Should write exactly one file")
    }

    @Test("writeSBOMs integration test with SPM graph")
    func writeSBOMsIntegrationTestWithSPMGraph() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
        let store = try SBOMTestStore.createSPMResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let _ = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
        #expect(files.count == 2, "Should generate both CycloneDX and SPDX files")

        // Verify both files are valid
        for filename in files {
            let filePath = outputDir.appending(component: filename)
            try self.verifyJSONFile(at: filePath)
        }
    }

    @Test("writeSBOMs integration test with Swiftly graph")
    func writeSBOMsIntegrationTestWithSwiftlyGraph() async throws {
        let outputDir = try createTempOutputDir()
        defer { try? cleanupTempDir(outputDir) }

        let graph = try SBOMTestModulesGraph.createSwiftlyModulesGraph()
        let store = try SBOMTestStore.createSwiftlyResolvedPackagesStore()
        let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
        let sbom = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: sbom)

        let _ = try await encoder.writeSBOMs(specs: [.cyclonedx, .spdx], outputDir: outputDir)

        let files = try localFileSystem.getDirectoryContents(outputDir)
        #expect(files.count == 2, "Should generate both CycloneDX and SPDX files")

        // Verify both files are valid
        for filename in files {
            let filePath = outputDir.appending(component: filename)
            try self.verifyJSONFile(at: filePath)
        }
    }
}
