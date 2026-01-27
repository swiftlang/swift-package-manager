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
import TSCUtility

internal struct SBOMEncoder {
    internal let sbom: SBOMDocument

    internal init(sbom: SBOMDocument) {
        self.sbom = sbom
    }

    internal func writeSBOMs(specs: [Spec], outputDir: AbsolutePath, filter: Filter = .all) async throws -> [AbsolutePath] {
        if !localFileSystem.exists(outputDir) {
            try localFileSystem.createDirectory(outputDir, recursive: true)
        }
        let specs = await Self.getSpecs(from: specs)
        var outputPaths: [AbsolutePath] = []
        for spec in specs {
            let outputPath = try await self.encodeSBOM(spec: spec, outputDir: outputDir, filter: filter)
            outputPaths.append(outputPath)
        }
        return outputPaths
    }

    internal func encodeSBOM(spec: SBOMSpec, outputDir: AbsolutePath, filter: Filter = .all) async throws -> AbsolutePath {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "_")
        let filename = "\(spec.concreteSpec)-\(spec.versionString)-\(self.sbom.primaryComponent.name)-\(self.sbom.primaryComponent.version.revision)-\(filter)-\(timestamp).json"
        let outputPath = outputDir.appending(component: filename)
        let encoded = try await encodeSBOMData(spec: spec)
        try localFileSystem.writeFileContents(outputPath, data: encoded)
        return outputPath
    }

    internal func encodeSBOMData(spec: SBOMSpec) async throws -> Data {
        let data: any Encodable = switch spec.concreteSpec {
        case .cyclonedx1:
            try await CycloneDXConverter.convertToCycloneDXDocument(from: self.sbom, spec: spec)
        case .spdx3:
            try await SPDXConverter.convertToSPDXGraph(from: self.sbom, spec: spec)
            // case .cyclonedx, .cyclonedx2:
            //     data = try await convertToCycloneDX2Document(from: sbom, spec: spec)
            // case .spdx, .spdx4:
            //     data = try await convertToSPDX4Graph(from: sbom, spec: spec)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)

        try await Self.validateSBOM(from: encoded, spec: spec)

        return encoded
    }

    internal static func getSpec(from spec: Spec) async -> SBOMSpec {
        return SBOMSpec(spec: spec)
    }

    internal static func getSpecs(from specs: [Spec]) async -> [SBOMSpec] {
        var result = Set<SBOMSpec>()
        for spec in specs {
            await result.insert(self.getSpec(from: spec))
        }
        return Array(result)
    }

    internal static func validateSBOM(from encoded: Foundation.Data, spec: SBOMSpec, bundleName: String = "SwiftPM_SBOMModel") async throws {
        guard let sbomJSONObject = try (JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else {
            throw SBOMEncoderError
                .jsonConversionFailed(message: "Could not convert generated SBOM file into JSON object for validation")
        }

        do {
            let schema = try await SBOMSchema(from: getSchemaFilename(from: spec), bundleName: bundleName)
            try await schema.validate(json: sbomJSONObject, spec: spec)
        } catch let error as SBOMSchemaError {
            if case .bundleNotFound(_) = error {
                // TODO echeng3805, handle this more nicely
                print("warning: \(error.errorDescription ?? "Bundle with schemas not found") - skipping SBOM validation")
                return
            }
            throw error
        }
    }

    private static func getSchemaFilename(from spec: SBOMSpec) throws -> String {
        switch spec.concreteSpec {
        case .cyclonedx1:
            CycloneDXConstants.cyclonedx1SchemaFile
        case .spdx3:
            SPDXConstants.spdx3SchemaFile
            // case .cyclonedx2:
            //     return CycloneDXConstants.cyclonedx2SchemaFile
            // case .spdx4:
            //     return SPDXConstants.spdx4SchemaFile
        }
    }
}

