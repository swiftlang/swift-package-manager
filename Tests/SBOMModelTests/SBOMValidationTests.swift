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

// MARK: - Test Helper for Loading Validators

/// Helper function to create a validator for tests by finding the SBOMModel module bundle
/// This bypasses the bundle search logic in production code which doesn't work in test contexts
fileprivate func createTestValidator(for spec: SBOMSpec) throws -> any SBOMValidatorProtocol {
    let schemaFilename = spec.schemaFilename
    
    // Find the SBOMModel bundle - schema files are resources of SBOMModel, not SBOMModelTests
    // Search for the bundle in the same directory as the test bundle
    let testBundleURL = Bundle.module.bundleURL
    let buildDir = testBundleURL.deletingLastPathComponent()
    
    // Try both .bundle and .resources extensions (macOS vs other platforms)
    let bundleExtensions = ["bundle", "resources"]
    var sbomModelBundle: Bundle?
    
    for ext in bundleExtensions {
        let bundleURL = buildDir.appendingPathComponent("SwiftPM_SBOMModel.\(ext)")
        if let bundle = Bundle(url: bundleURL) {
            sbomModelBundle = bundle
            break
        }
    }
    
    guard let bundle = sbomModelBundle,
          let schemaURL = bundle.url(forResource: schemaFilename, withExtension: "json") else {
        throw SBOMSchemaError.schemaFileNotFound(filename: schemaFilename, bundlePath: buildDir.path)
    }
    
    let schemaData = try Data(contentsOf: schemaURL)
    guard let jsonObject = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
        throw SBOMSchemaError.invalidSchemaFormat(message: "Could not parse schema as JSON dictionary")
    }
    
    // Create the appropriate validator based on spec type
    switch spec.concreteSpec {
    case .cyclonedx1:
        return CycloneDXValidator(schema: jsonObject)
    case .spdx3:
        return SPDXValidator(schema: jsonObject)
    }
}

@Suite(
    .tags(
        .Feature.SBOM,
        .TestSize.medium
    )
)
struct SBOMValidationTests {
    struct ValidateGraphSBOMTestCase: CustomStringConvertible {
        let graphName: String
        let inputSpec: SBOMSpec
        let inputGraph: ModulesGraph
        let inputStore: ResolvedPackagesStore
        let wantError: Bool

        var description: String { // don't print the graph because it's large
            "ValidateGraphSBOMTestCase(graph: \(self.graphName), spec: \(self.inputSpec), wantError: \(self.wantError))"
        }
    }

    static func getValidateGraphSBOMTestCases() throws -> [ValidateGraphSBOMTestCase] {
        try [
            ValidateGraphSBOMTestCase(
                graphName: "SwiftPM",
                inputSpec: SBOMSpec(spec: .cyclonedx),
                inputGraph: SBOMTestModulesGraph.createSPMModulesGraph(),
                inputStore: SBOMTestStore.createSPMResolvedPackagesStore(),
                wantError: false
            ),
            ValidateGraphSBOMTestCase(
                graphName: "SwiftPM",
                inputSpec: SBOMSpec(spec: .spdx),
                inputGraph: SBOMTestModulesGraph.createSPMModulesGraph(),
                inputStore: SBOMTestStore.createSPMResolvedPackagesStore(),
                wantError: false
            ),
            ValidateGraphSBOMTestCase(
                graphName: "Swiftly",
                inputSpec: SBOMSpec(spec: .cyclonedx),
                inputGraph: SBOMTestModulesGraph.createSwiftlyModulesGraph(),
                inputStore: SBOMTestStore.createSwiftlyResolvedPackagesStore(),
                wantError: false
            ),
            ValidateGraphSBOMTestCase(
                graphName: "Swiftly",
                inputSpec: SBOMSpec(spec: .spdx),
                inputGraph: SBOMTestModulesGraph.createSwiftlyModulesGraph(),
                inputStore: SBOMTestStore.createSwiftlyResolvedPackagesStore(),
                wantError: false
            ),
        ]
    }

    @Test("validate SBOM from graphs", arguments: try getValidateGraphSBOMTestCases())
    func validateSBOMFromGraph(testCase: ValidateGraphSBOMTestCase) async throws {
        let extractor = SBOMExtractor(
            modulesGraph: testCase.inputGraph,
            dependencyGraph: nil,
            store: testCase.inputStore
        )
        let document = try await extractor.extractSBOM()
        let observability = ObservabilitySystem.makeForTesting()
        let encoder = SBOMEncoder(sbom: document, observabilityScope: observability.topScope)
        let encodedData = try await encoder.encodeSBOMData(spec: testCase.inputSpec)
        
        guard let sbomJSONObject = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] else {
            throw SBOMEncoderError.jsonConversionFailed(message: "Could not convert generated SBOM file into JSON object for validation")
        }
        
        let validator = try createTestValidator(for: testCase.inputSpec)
        try await validator.validate(sbomJSONObject)
    }

    struct ValidateFileSBOMTestCase {
        let inputFilePath: String
        let inputSBOMSpec: SBOMSpec
        let wantEncoderError: Bool
        let wantValidatorError: Bool
    }

    static func getValidateFileSBOMTestCases() throws -> [ValidateFileSBOMTestCase] {
        [
            // valid CycloneDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-empty-comps",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-minimal",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-unicode",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-spm",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-versions",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: false,
            ),

            // valid SPDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-spdx-3.0.1-spm",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantEncoderError: false,
                wantValidatorError: false,
            ),

            // invalid CycloneDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1-missing-fields",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: true,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1-small",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: true,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1.7-uppercase-uuid",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: true,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1.7-wrong-bomformat",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantEncoderError: false,
                wantValidatorError: true,
            ),

            // invalid SPDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3-small",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantEncoderError: true,
                wantValidatorError: false,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-no-iri",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantEncoderError: false,
                wantValidatorError: true,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-spm",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantEncoderError: false,
                wantValidatorError: true,
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-wrong-relationshiptype",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantEncoderError: false,
                wantValidatorError: true,
            ),
        ]
    }

    @Test("validate SBOM from files", arguments: try getValidateFileSBOMTestCases())
    func validateSBOMFromFile(testCase: ValidateFileSBOMTestCase) async throws {
        let testBundle = Bundle.module
        let fileURL = try #require(
            testBundle.url(forResource: testCase.inputFilePath, withExtension: "json"),
            "Could not find \(testCase.inputFilePath).json test file"
        )
        let encodedData = try Data(contentsOf: fileURL)
        
        if testCase.wantEncoderError {
            // For invalid files, we expect either JSON parsing errors (NSError) or validation errors (SBOMEncoderError)
            // Try to parse the SBOM data - if this fails, that's expected
            #expect(throws: SBOMEncoderError.self) {
                do {
                    guard let _ = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] else {
                        throw SBOMEncoderError.jsonConversionFailed(message: "Unexpected encoding error in test")
                    }
                } catch let error as SBOMEncoderError {
                    throw error
                } catch let error as NSError {
                    throw SBOMEncoderError.jsonConversionFailed(message: "JSON parsing failed: \(error.localizedDescription)")
                }
            }
            return // Don't continue with validation if we expected an encoder error
        }
        guard let sbomJSONObject = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] else {
            throw SBOMEncoderError.jsonConversionFailed(message: "Unexpected encoding error in test")
        }
        let validator = try createTestValidator(for: testCase.inputSBOMSpec)
        if testCase.wantValidatorError {
            await #expect(throws: SBOMValidatorError.self) {
                try await validator.validate(sbomJSONObject)
            }
        } else {
            try await validator.validate(sbomJSONObject)
        }
    }
}
