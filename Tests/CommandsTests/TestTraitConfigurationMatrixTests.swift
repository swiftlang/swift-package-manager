//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Commands

import PackageModel
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        Tag.TestSize.small,
        Tag.Feature.Command.Test,
    )
)
struct TestTraitConfigurationMatrixTests {
    private func testTarget(
        _ name: String,
        traitConfigurations: [TraitConfiguration]? = nil
    ) throws -> TargetDescription {
        try TargetDescription(name: name, type: .test, traitConfigurations: traitConfigurations)
    }

    @Test
    func groupsTargetsByConfigurationInDeclarationOrder() throws {
        let matrix = SwiftTestCommand.testTraitConfigurationMatrix(testTargets: [
            try testTarget("ATests", traitConfigurations: [.enabledTraits(["Foo"]), .default]),
            try testTarget("BTests", traitConfigurations: [.enableAllTraits, .enabledTraits(["Foo"])]),
        ])

        #expect(matrix.map(\.configuration) == [.enabledTraits(["Foo"]), .default, .enableAllTraits])
        #expect(matrix[0].testTargets == ["ATests", "BTests"])
        #expect(matrix[1].testTargets == ["ATests"])
        #expect(matrix[2].testTargets == ["BTests"])
    }

    @Test
    func undeclaredTargetsGroupUnderDefault() throws {
        let matrix = SwiftTestCommand.testTraitConfigurationMatrix(testTargets: [
            try testTarget("ATests", traitConfigurations: [.disableAllTraits]),
            try testTarget("BTests"),
        ])

        #expect(matrix.map(\.configuration) == [.disableAllTraits, .default])
        #expect(matrix[1].testTargets == ["BTests"])
    }

    @Test
    func deduplicatesEquivalentConfigurationsKeepingFirstOccurrence() throws {
        let matrix = SwiftTestCommand.testTraitConfigurationMatrix(testTargets: [
            try testTarget("ATests", traitConfigurations: [.enabledTraits(["Foo", "Bar"])]),
            try testTarget("BTests", traitConfigurations: [.default, .enabledTraits(["Bar", "Foo"])]),
        ])

        // The set-based configurations are equal regardless of spelling order.
        #expect(matrix.map(\.configuration) == [.enabledTraits(["Foo", "Bar"]), .default])
        #expect(matrix[0].testTargets == ["ATests", "BTests"])
    }

    @Test
    func ignoresNonTestTargets() throws {
        let matrix = SwiftTestCommand.testTraitConfigurationMatrix(testTargets: [
            try TargetDescription(name: "Lib", type: .regular),
            try testTarget("LibTests"),
        ])

        #expect(matrix.map(\.configuration) == [.default])
        #expect(matrix[0].testTargets == ["LibTests"])
    }

    @Test
    func emptyInputProducesEmptyMatrix() {
        #expect(SwiftTestCommand.testTraitConfigurationMatrix(testTargets: []).isEmpty)
    }

    @Test
    func duplicateDeclarationWithinOneTargetIsHarmless() throws {
        let matrix = SwiftTestCommand.testTraitConfigurationMatrix(testTargets: [
            try testTarget("ATests", traitConfigurations: [.default, .default]),
        ])

        #expect(matrix.count == 1)
        #expect(matrix[0].testTargets == ["ATests"])
    }
}
