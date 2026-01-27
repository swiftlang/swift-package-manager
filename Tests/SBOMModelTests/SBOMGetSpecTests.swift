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

struct SBOMGetSpecTests {
    struct GetSpecTestCase {
        let input: Spec
        let expectedConcreteSpec: SBOMSpec.ConcreteSpec
        let expectedVersion: String
    }

    static let specTestCases: [GetSpecTestCase] = [
        GetSpecTestCase(
            input: .cyclonedx,
            expectedConcreteSpec: .cyclonedx1,
            expectedVersion: CycloneDXConstants.cyclonedx1SpecVersion
        ),
        GetSpecTestCase(
            input: .cyclonedx1,
            expectedConcreteSpec: .cyclonedx1,
            expectedVersion: CycloneDXConstants.cyclonedx1SpecVersion
        ),
        GetSpecTestCase(
            input: .spdx,
            expectedConcreteSpec: .spdx3,
            expectedVersion: SPDXConstants.spdx3SpecVersion
        ),
        GetSpecTestCase(
            input: .spdx3,
            expectedConcreteSpec: .spdx3,
            expectedVersion: SPDXConstants.spdx3SpecVersion
        ),
    ]

    @Test("getSpec good weather", arguments: specTestCases)
    func getSpecParameterized(testCase: GetSpecTestCase) async throws {
        let spec = await SBOMEncoder.getSpec(from: testCase.input)

        #expect(spec.concreteSpec == testCase.expectedConcreteSpec)
        #expect(spec.versionString == testCase.expectedVersion)
    }

    // MARK: - getSpecs Tests

    @Test("getSpecs returns unique specs")
    func getSpecsReturnsUniqueSpecs() async throws {
        let specs = await SBOMEncoder.getSpecs(from: [.cyclonedx, .cyclonedx1, .spdx, .spdx3])

        #expect(specs.count == 2, "Should return only unique specs")

        let types = Set(specs.map(\.concreteSpec))
        #expect(types.contains(.cyclonedx1))
        #expect(types.contains(.spdx3))
    }

    @Test("getSpecs handles empty array")
    func getSpecsHandlesEmptyArray() async throws {
        let specs = await SBOMEncoder.getSpecs(from: [])

        #expect(specs.isEmpty, "Should return empty array for empty input")
    }

    @Test("getSpecs handles single spec")
    func getSpecsHandlesSingleSpec() async throws {
        let specs = await SBOMEncoder.getSpecs(from: [.cyclonedx])

        #expect(specs.count == 1)
        #expect(specs[0].concreteSpec == .cyclonedx1)
    }
}
