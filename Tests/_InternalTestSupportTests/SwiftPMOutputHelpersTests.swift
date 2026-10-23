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

import Basics
import CoreCommands
import SPMBuildCore
import Testing

import _InternalTestSupport

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct SwiftPMOutputHelpersTests {

    @Test
    func testFilterString() async throws {
        let expected = [
            "what is this"
        ]
        let content = expected.joined(separator: "\n")
        let logLevelFilter: LogLevelFilter? = nil


        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: logLevelFilter,
        )

        #expect(filtered == expected)
    }

    @Test(
        arguments: [
            (
                content: "",
                expected: [String](),
                id: "Empty content returns empty array",
            ),
            (
                content: "a single line of output",
                expected: ["a single line of output"],
                id: "Single line without trailing newline is preserved",
            ),
            (
                content: "line one\nline two\nline three",
                expected: ["line one", "line two", "line three"],
                id: "Multiline content is split on newlines",
            ),
            (
                content: "line one\n\nline two",
                expected: ["line one", "line two"],
                id: "Empty lines between content are omitted",
            ),
            (
                content: "\n\n",
                expected: [String](),
                id: "Content with only newlines returns empty array",
            ),
        ]
    )
    func noFilterLevelReturnsLinesWithoutLevelFiltering(
        content: String,
        expected: [String],
        id: String,
    ) async throws {
        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: nil,
        )

        #expect(filtered == expected)
    }

    @Test(
        arguments: [
            (
                excludedLine: "ld: warning: building for macOS, but linking with dylib 'libfoo' which was built for newer version 11",
                id: "Linker warning about dylib newer major version is excluded",
            ),
            (
                excludedLine: "ld: warning: building for iOS, but linking with dylib '/path/to/libbar.dylib' which was built for newer version 15.1",
                id: "Linker warning about dylib newer major.minor version is excluded",
            ),
            (
                excludedLine: "some output [logging] from the build",
                id: "Line containing [logging] marker is excluded",
            ),
            (
                excludedLine: "note: Unable to locate libSwiftScan in the toolchain",
                id: "Line containing 'Unable to locate libSwiftScan' is excluded",
            ),
            (
                excludedLine: "warning: something occurred: unable to find libclang on PATH",
                id: "Warning line that is unable to find libclang is excluded",
            ),
        ]
    )
    func knownNoiseLinesAreExcludedWhenNoFilterLevel(
        excludedLine: String,
        id: String,
    ) async throws {
        let keepBefore = "keep this line before"
        let keepAfter = "keep this line after"
        let content = [
            keepBefore,
            excludedLine,
            keepAfter,
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: nil,
        )

        #expect(filtered == [keepBefore, keepAfter])
    }

    @Test(
        arguments: [
            BuildSystemProvider.Kind.native,
            BuildSystemProvider.Kind.xcode,
        ]
    )
    func deprecatedBuildSystemWarningIsExcluded(
        _ buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let deprecationMessage = Basics.Diagnostic.deprecatedBuildSystem(
            buildSystem: buildSystem,
        ).message
        let keep = "keep this unrelated line"
        let content = [
            keep,
            "warning: \(deprecationMessage)",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: nil,
        )

        #expect(filtered == [keep])
    }

    @Test
    func deprecatedBuildSystemWarningForSwiftbuildIsNotExcluded() async throws {
        let swiftbuildDeprecationLine =
            "warning: '--build-system swiftbuild' has been deprecated"

        let filtered = filterSwiftPMOutput(
            content: swiftbuildDeprecationLine,
            filterLevel: nil,
        )

        #expect(filtered == [swiftbuildDeprecationLine])
    }

    @Test
    func warningFilterRetainsOnlyLinesContainingWarning() async throws {
        let content = [
            "warning: deprecated API usage",
            "error: compilation failed",
            "note: an informational message",
            "another warning: foo was removed",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: .warning,
        )

        #expect(filtered == [
            "warning: deprecated API usage",
            "another warning: foo was removed",
        ])
    }

    @Test
    func errorFilterRetainsOnlyLinesContainingError() async throws {
        let content = [
            "warning: deprecated API usage",
            "error: compilation failed",
            "note: an informational message",
            "another error: linker died",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: .error,
        )

        #expect(filtered == [
            "error: compilation failed",
            "another error: linker died",
        ])
    }

    @Test
    func warningFilterStillAppliesNoiseExclusions() async throws {
        let keep = "warning: deprecated API usage"
        let content = [
            keep,
            "ld: warning: building for macOS, but linking with dylib 'libfoo' which was built for newer version 11",
            "warning: something occurred: unable to find libclang on PATH",
            "warning: [logging] internal diagnostic",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: .warning,
        )

        #expect(filtered == [keep])
    }

    @Test
    func errorFilterStillAppliesNoiseExclusions() async throws {
        let keep = "error: compilation failed"
        let content = [
            keep,
            "error: [logging] internal diagnostic",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: .error,
        )

        #expect(filtered == [keep])
    }

    @Test
    func warningFilterReturnsEmptyWhenNoLineContainsWarning() async throws {
        let content = [
            "info: nothing to see here",
            "another informational message",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: .warning,
        )

        #expect(filtered == [])
    }

    @Test
    func libclangExclusionRequiresBothWarningPrefixAndUnableToFind() async throws {
        let onlyLibclangMention = "note: libclang version mismatch detected"
        let onlyUnableToFind = "note: unable to find a toolchain file"
        let bothButNoWarningPrefix =
            "info: unable to find libclang in the usual places"

        let content = [
            onlyLibclangMention,
            onlyUnableToFind,
            bothButNoWarningPrefix,
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: nil,
        )

        #expect(filtered == [
            onlyLibclangMention,
            onlyUnableToFind,
            bothButNoWarningPrefix,
        ])
    }

    @Test
    func linkerWarningForOlderDylibVersionIsNotExcluded() async throws {
        let olderVersionLine =
            "ld: warning: building for macOS, but linking with dylib 'libfoo' which was built for older version 10"

        let filtered = filterSwiftPMOutput(
            content: olderVersionLine,
            filterLevel: nil,
        )

        #expect(filtered == [olderVersionLine])
    }

    @Test
    func allExclusionsCombinedProduceEmptyResult() async throws {
        let nativeDeprecation = Basics.Diagnostic.deprecatedBuildSystem(
            buildSystem: .native,
        ).message
        let xcodeDeprecation = Basics.Diagnostic.deprecatedBuildSystem(
            buildSystem: .xcode,
        ).message
        let content = [
            "ld: warning: building for macOS, but linking with dylib 'libfoo' which was built for newer version 11",
            "something [logging] here",
            "Unable to locate libSwiftScan",
            "warning: oops: unable to find libclang",
            "warning: \(nativeDeprecation)",
            "warning: \(xcodeDeprecation)",
        ].joined(separator: "\n")

        let filtered = filterSwiftPMOutput(
            content: content,
            filterLevel: nil,
        )

        #expect(filtered == [])
    }
}
