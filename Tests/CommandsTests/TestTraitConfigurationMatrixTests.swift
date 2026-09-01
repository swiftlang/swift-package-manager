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
    func buildDirectorySuffixes() {
        // The default configuration shares the regular build directory.
        #expect(TraitConfiguration.default.buildDirectorySuffix == "")
        #expect(TraitConfiguration.enableAllTraits.buildDirectorySuffix == "+all-traits")
        #expect(TraitConfiguration.disableAllTraits.buildDirectorySuffix == "+no-traits")
        // Trait names are sorted so equivalent sets produce the same directory.
        #expect(
            TraitConfiguration.enabledTraits(["Foo", "Bar"]).buildDirectorySuffix == "+traits-Bar-Foo"
        )
        #expect(
            TraitConfiguration.enabledTraits(["Bar", "Foo"]).buildDirectorySuffix ==
            TraitConfiguration.enabledTraits(["Foo", "Bar"]).buildDirectorySuffix
        )
    }

    @Test
    func buildDirectorySuffixForLongTraitListsUsesDigest() {
        let manyTraits = Set((0..<50).map { "Trait\($0)" })
        let suffix = TraitConfiguration.enabledTraits(manyTraits).buildDirectorySuffix
        // Long lists collapse to a fixed-length digest, deterministically.
        #expect(suffix.hasPrefix("+traits-"))
        #expect(suffix.count == "+traits-".count + 16)
        #expect(suffix == TraitConfiguration.enabledTraits(manyTraits).buildDirectorySuffix)
    }

    @Test
    func buildDirectorySuffixForNonIdentifierNamesUsesDigest() {
        // Trait names are validated to be identifiers, but the encoding doesn't
        // rely on that invariant holding elsewhere: names that could make the
        // joined spelling ambiguous (e.g. containing the separator) fall back
        // to the digest form, so distinct configurations can't share a
        // build directory.
        let ambiguousOne = TraitConfiguration.enabledTraits(["A-B"]).buildDirectorySuffix
        let ambiguousTwo = TraitConfiguration.enabledTraits(["A", "B"]).buildDirectorySuffix
        #expect(ambiguousOne.hasPrefix("+traits-"))
        #expect(ambiguousOne.count == "+traits-".count + 16)
        #expect(ambiguousOne != ambiguousTwo)
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
