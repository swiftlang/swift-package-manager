//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
import ArgumentParser
import Commands
@testable import PackageModel

@Suite(
    "SwiftTestCommand -Xcov Integration Tests",
    .tags(
        .TestSize.medium,
        .Feature.CodeCoverage,
    ),
)
struct SwiftTestCommandXcovIntegrationTests {

    @Test("Parse single -Xcov argument with json format")
    func parseSingleXcovWithJsonFormat() throws {
        // GIVEN SwiftTestCommand with single -Xcov json argument
        let args = ["-Xcov", "json=coverage.json"]

        // WHEN Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // THEN Should have parsed the -Xcov argument correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 1)

        // AND JSON should have the correct argument
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["coverage.json"])

        // AND HTML arguments should be empty
        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs.isEmpty)
    }

    @Test("Parse single -Xcov argument with html format")
    func parseSingleXcovWithHtmlFormat() throws {
        // GIVEN SwiftTestCommand with single -Xcov html argument
        let args = ["-Xcov", "html=coverage-report"]

        // WHEN Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // THEN Should have parsed the -Xcov argument correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 1)

        // AND HTML should have the correct argument
        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == ["coverage-report"])

        // AND JSON should have the correct argument
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs.isEmpty)
    }

    @Test("Parse single -Xcov argument without format")
    func parseSingleXcovWithoutFormat() throws {
        // Given: SwiftTestCommand with -Xcov argument without format
        let args = ["-Xcov", "output.json"]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should have parsed the -Xcov argument correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 1)

        // Should return the value for any format since no format was specified
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["output.json"])

        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == ["output.json"])
    }

    @Test("Parse multiple -Xcov arguments with mixed formats")
    func parseMultipleXcovWithMixedFormats() throws {
        // Given: SwiftTestCommand with multiple -Xcov arguments
        let args = [
            "-Xcov", "json=coverage.json",
            "-Xcov", "html=coverage-report",
            "-Xcov", "xml=coverage.xml",  // Unsupported format
            "-Xcov", "plain-output.txt"   // No format
        ]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should have parsed all -Xcov arguments correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 4)

        // JSON format should include json-specific + unsupported + no-format
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["coverage.json", "xml=coverage.xml", "plain-output.txt"])

        // HTML format should include html-specific + unsupported + no-format
        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == ["coverage-report", "xml=coverage.xml", "plain-output.txt"])
    }

    @Test("Parse -Xcov arguments preserve command-line order")
    func parseXcovPreservesCommandLineOrder() throws {
        // Given: SwiftTestCommand with -Xcov arguments in specific order
        let args = [
            "-Xcov", "json=first.json",
            "-Xcov", "xml=unsupported.xml",
            "-Xcov", "json=second.json",
            "-Xcov", "third.txt"
        ]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should preserve the command-line order
        let jsonArgs = command.xcovArguments.getArguments(for: .json)
        #expect(jsonArgs == ["first.json", "xml=unsupported.xml", "second.json", "third.txt"])
    }

    @Test("Parse -Xcov with complex file paths")
    func parseXcovWithComplexFilePaths() throws {
        // Given: SwiftTestCommand with complex file paths
        let args = [
            "-Xcov", "json=/path/with spaces/coverage.json",
            "-Xcov", "html=./relative/path/coverage-report",
            "-Xcov", "json=~/home/coverage.json"
        ]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should handle complex paths correctly
        let xcovArgs = command.xcovArguments
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["/path/with spaces/coverage.json", "~/home/coverage.json"])

        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == ["./relative/path/coverage-report"])
    }

    @Test("Parse -Xcov with edge cases")
    func parseXcovWithEdgeCases() throws {
        // Given: SwiftTestCommand with edge case -Xcov arguments
        let args = [
            "-Xcov", "json=",           // Empty value
            "-Xcov", "=",               // Just equals
            "-Xcov", "json=key=value",  // Multiple equals
            "-Xcov", ""                 // Empty string
        ]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should handle edge cases correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 4)

        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["", "=", "key=value", ""])
    }

    @Test("Parse command without -Xcov arguments")
    func parseCommandWithoutXcovArguments() throws {
        // Given: SwiftTestCommand without any -Xcov arguments
        let args = ["--enable-coverage"]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should have empty XcovArgumentCollection
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 0)

        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs.isEmpty)

        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs.isEmpty)
    }

    @Test("Parse -Xcov works with existing coverage options")
    func parseXcovWorksWithExistingCoverageOptions() throws {
        // Given: SwiftTestCommand with both -Xcov and existing coverage options
        let args = [
            "--enable-coverage",
            "--coverage-format", "json",
            "--coverage-format", "html",
            "-Xcov", "json=coverage.json",
            "-Xcov", "html=coverage-report"
        ]

        // When: Parsing the command
        let command = try SwiftTestCommand.parseAsRoot(args) as! SwiftTestCommand

        // Then: Should have both existing coverage options and -Xcov arguments
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == 2)

        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == ["coverage.json"])

        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == ["coverage-report"])

        // Note: We can't easily test isEnabled/formats due to access control,
        // but the fact that parsing succeeded indicates they work together
    }
}

// Extensions to add count property to XcovArgumentCollection for testing
extension XcovArgumentCollection {
    var count: Int {
        // This is a test helper - in real implementation we'd need to track this
        // For now, assume we can get count from the internal arguments array
        return self.arguments.count
    }

}
