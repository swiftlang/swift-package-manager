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
        .Feature.SBOM,
        .TestSize.small
    )
)
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

    @Test("internalSpec good weather", arguments: specTestCases)
    func getSpecParameterized(testCase: GetSpecTestCase) throws {
        let spec = testCase.input.internalSpec()

        #expect(spec.concreteSpec == testCase.expectedConcreteSpec)
        #expect(spec.versionString == testCase.expectedVersion)
    }

    // MARK: - Multiple Specs Tests

    @Test("internalSpec returns unique specs")
    func getSpecsReturnsUniqueSpecs() throws {
        let inputSpecs: [Spec] = [.cyclonedx, .cyclonedx1, .spdx, .spdx3]
        let specs = Array(Set(inputSpecs.map { $0.internalSpec() })).sorted()

        #expect(specs.count == 2, "Should return only unique specs")

        let types = Set(specs.map(\.concreteSpec))
        #expect(types.contains(.cyclonedx1))
        #expect(types.contains(.spdx3))
    }

    @Test("internalSpec handles empty array")
    func getSpecsHandlesEmptyArray() throws {
        let inputSpecs: [Spec] = []
        let specs = Array(Set(inputSpecs.map { $0.internalSpec() })).sorted()

        #expect(specs.isEmpty, "Should return empty array for empty input")
    }

    @Test("internalSpec handles single spec")
    func getSpecsHandlesSingleSpec() throws {
        let inputSpecs: [Spec] = [.cyclonedx]
        let specs = Array(Set(inputSpecs.map { $0.internalSpec() })).sorted()

        #expect(specs.count == 1)
        #expect(specs[0].concreteSpec == .cyclonedx1)
    }
}
