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

    @Test("validate SBOM from graphs", .skip("TODO echeng3805, Schema bundles can't be found"), arguments: try getValidateGraphSBOMTestCases())
    func validateSBOMFromGraph(testCase: ValidateGraphSBOMTestCase) async throws {
        let extractor = SBOMExtractor(
            modulesGraph: testCase.inputGraph,
            dependencyGraph: nil,
            store: testCase.inputStore
        )
        let document = try await extractor.extractSBOM()
        let encoder = SBOMEncoder(sbom: document)
        let encodedData = try await encoder.encodeSBOMData(spec: testCase.inputSpec)

        if testCase.wantError {
            await #expect(throws: StringError.self) {
                try await SBOMEncoder.validateSBOM(from: encodedData, spec: testCase.inputSpec)
            }
        } else {
            try await SBOMEncoder.validateSBOM(from: encodedData, spec: testCase.inputSpec)
        }
    }

    struct ValidateFileSBOMTestCase {
        let inputFilePath: String
        let inputSBOMSpec: SBOMSpec
        let wantError: Bool
    }

    static func getValidateFileSBOMTestCases() throws -> [ValidateFileSBOMTestCase] {
        [
            // valid CycloneDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-empty-comps",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: false
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-minimal",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: false
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-unicode",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: false
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-spm",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: false
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-cyclonedx-1.7-versions",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: false
            ),

            // valid SPDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/valid-spdx-3.0.1-spm",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantError: false
            ),

            // invalid CycloneDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1-missing-fields",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1-small",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1.7-uppercase-uuid",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-cyclonedx-1.7-wrong-bomformat",
                inputSBOMSpec: SBOMSpec(spec: .cyclonedx1),
                wantError: true
            ),

            // invalid SPDX SBOMs
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3-small",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-no-iri",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-spm",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantError: true
            ),
            ValidateFileSBOMTestCase(
                inputFilePath: "testfiles/invalid-spdx-3.0.1-wrong-relationshiptype",
                inputSBOMSpec: SBOMSpec(spec: .spdx3),
                wantError: true
            ),
        ]
    }

    @Test("validate SBOM from files", .skip("TODO echeng3805, Schema bundles can't be found"), arguments: try getValidateFileSBOMTestCases())
    func validateSBOMFromFile(testCase: ValidateFileSBOMTestCase) async throws {
        let testBundle = Bundle.module
        let fileURL = try #require(
            testBundle.url(forResource: testCase.inputFilePath, withExtension: "json"),
            "Could not find \(testCase.inputFilePath).json test file"
        )
        let encodedData = try Data(contentsOf: fileURL)

        if testCase.wantError {
            await #expect(throws: (any Error).self) {
                try await SBOMEncoder.validateSBOM(from: encodedData, spec: testCase.inputSBOMSpec)
            }
        } else {
            try await SBOMEncoder.validateSBOM(from: encodedData, spec: testCase.inputSBOMSpec)
        }
    }
}
