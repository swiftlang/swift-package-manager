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

/// Categories for different types of integration tests
enum IntegrationTestCategory {
    case singleArgument
    case multipleArguments
    case edgeCases
    case compatibility
    case ordering
}

/// Test data for SwiftTestCommand -Xcov integration scenarios
struct IntegrationTestData {
    let category: IntegrationTestCategory
    let description: String
    let commandLineArgs: [String]
    let expectedXcovArgumentCount: Int
    let expectedJsonArgs: [String]
    let expectedHtmlArgs: [String]
}

@Suite(
    "SwiftTestCommand -Xcov Integration Tests",
    .tags(
        .TestSize.medium,
        .Feature.CodeCoverage,
    ),
)
struct SwiftTestCommandXcovIntegrationTests {

    @Test(
        "SwiftTestCommand -Xcov Integration Test",
        arguments: [
            // MARK: - Single Argument Tests
            IntegrationTestData(
                category: .singleArgument,
                description: "Parse single -Xcov argument with json format",
                commandLineArgs: ["-Xcov", "json=coverage.json"],
                expectedXcovArgumentCount: 1,
                expectedJsonArgs: ["coverage.json"],
                expectedHtmlArgs: []
            ),
            IntegrationTestData(
                category: .singleArgument,
                description: "Parse single -Xcov argument with html format",
                commandLineArgs: ["-Xcov", "html=coverage-report"],
                expectedXcovArgumentCount: 1,
                expectedJsonArgs: [],
                expectedHtmlArgs: ["coverage-report"]
            ),
            IntegrationTestData(
                category: .singleArgument,
                description: "Parse single -Xcov argument without format",
                commandLineArgs: ["-Xcov", "output.json"],
                expectedXcovArgumentCount: 1,
                expectedJsonArgs: ["output.json"],
                expectedHtmlArgs: ["output.json"]
            ),
            // MARK: - Multiple Arguments Tests
            IntegrationTestData(
                category: .multipleArguments,
                description: "Parse multiple -Xcov arguments with mixed formats",
                commandLineArgs: [
                    "-Xcov", "json=coverage.json",
                    "-Xcov", "html=coverage-report",
                    "-Xcov", "xml=coverage.xml",  // Unsupported format
                    "-Xcov", "plain-output.txt"   // No format
                ],
                expectedXcovArgumentCount: 4,
                expectedJsonArgs: ["coverage.json", "xml=coverage.xml", "plain-output.txt"],
                expectedHtmlArgs: ["coverage-report", "xml=coverage.xml", "plain-output.txt"]
            ),
            IntegrationTestData(
                category: .multipleArguments,
                description: "Parse -Xcov with complex file paths",
                commandLineArgs: [
                    "-Xcov", "json=/path/with spaces/coverage.json",
                    "-Xcov", "html=./relative/path/coverage-report",
                    "-Xcov", "json=~/home/coverage.json"
                ],
                expectedXcovArgumentCount: 3,
                expectedJsonArgs: ["/path/with spaces/coverage.json", "~/home/coverage.json"],
                expectedHtmlArgs: ["./relative/path/coverage-report"]
            ),
            // MARK: - Ordering Tests
            IntegrationTestData(
                category: .ordering,
                description: "Parse -Xcov arguments preserve command-line order",
                commandLineArgs: [
                    "-Xcov", "json=first.json",
                    "-Xcov", "xml=unsupported.xml",
                    "-Xcov", "json=second.json",
                    "-Xcov", "third.txt"
                ],
                expectedXcovArgumentCount: 4,
                expectedJsonArgs: ["first.json", "xml=unsupported.xml", "second.json", "third.txt"],
                expectedHtmlArgs: ["xml=unsupported.xml", "third.txt"]
            ),
            // MARK: - Edge Cases Tests
            IntegrationTestData(
                category: .edgeCases,
                description: "Parse -Xcov with edge cases",
                commandLineArgs: [
                    "-Xcov", "json=",           // Empty value
                    "-Xcov", "=",               // Just equals
                    "-Xcov", "json=key=value",  // Multiple equals
                    "-Xcov", ""                 // Empty string
                ],
                expectedXcovArgumentCount: 4,
                expectedJsonArgs: ["", "=", "key=value", ""],
                expectedHtmlArgs: ["=", ""]
            ),
            IntegrationTestData(
                category: .edgeCases,
                description: "Parse command without -Xcov arguments",
                commandLineArgs: ["--enable-coverage"],
                expectedXcovArgumentCount: 0,
                expectedJsonArgs: [],
                expectedHtmlArgs: []
            ),
            // MARK: - Compatibility Tests
            IntegrationTestData(
                category: .compatibility,
                description: "Parse -Xcov works with existing coverage options",
                commandLineArgs: [
                    "--enable-coverage",
                    "--coverage-format", "json",
                    "--coverage-format", "html",
                    "-Xcov", "json=coverage.json",
                    "-Xcov", "html=coverage-report"
                ],
                expectedXcovArgumentCount: 2,
                expectedJsonArgs: ["coverage.json"],
                expectedHtmlArgs: ["coverage-report"]
            ),
            IntegrationTestData(
                category: .compatibility,
                description: "Parse -Xcov with other test command options",
                commandLineArgs: [
                    "--enable-coverage",
                    "--parallel",
                    "-Xcov", "json=coverage.json",
                    "--filter", "SomeTests",
                    "-Xcov", "html=coverage-report"
                ],
                expectedXcovArgumentCount: 2,
                expectedJsonArgs: ["coverage.json"],
                expectedHtmlArgs: ["coverage-report"]
            ),
            // MARK: - Real World Scenarios
            IntegrationTestData(
                category: .multipleArguments,
                description: "Parse realistic mix of -Xcov arguments",
                commandLineArgs: [
                    "-Xcov", "json=./build/coverage.json",
                    "-Xcov", "html=./build/coverage-report",
                    "-Xcov", "lcov=./build/coverage.lcov",  // Unsupported
                    "-Xcov", "exclude-paths=/tmp/*",        // Generic flag (no leading dashes)
                    "-Xcov", "xml=./build/cobertura.xml"    // Unsupported
                ],
                expectedXcovArgumentCount: 5,
                expectedJsonArgs: [
                    "./build/coverage.json",
                    "lcov=./build/coverage.lcov",
                    "exclude-paths=/tmp/*",
                    "xml=./build/cobertura.xml"
                ],
                expectedHtmlArgs: [
                    "./build/coverage-report",
                    "lcov=./build/coverage.lcov",
                    "exclude-paths=/tmp/*",
                    "xml=./build/cobertura.xml"
                ]
            ),
        ],
    )
    func swiftTestCommandXcovIntegration(testData: IntegrationTestData) throws {
        // WHEN: Parsing the command with the test data arguments
        let command = try SwiftTestCommand.parseAsRoot(testData.commandLineArgs) as! SwiftTestCommand

        // THEN: Should have parsed the -Xcov arguments correctly
        let xcovArgs = command.xcovArguments
        #expect(xcovArgs.count == testData.expectedXcovArgumentCount, "Expected \(testData.expectedXcovArgumentCount) arguments, got \(xcovArgs.count) for: \(testData.description)")

        // AND: JSON arguments should match expectations
        let jsonArgs = xcovArgs.getArguments(for: .json)
        #expect(jsonArgs == testData.expectedJsonArgs, "JSON args mismatch for: \(testData.description). Expected: \(testData.expectedJsonArgs), Got: \(jsonArgs)")

        // AND: HTML arguments should match expectations
        let htmlArgs = xcovArgs.getArguments(for: .html)
        #expect(htmlArgs == testData.expectedHtmlArgs, "HTML args mismatch for: \(testData.description). Expected: \(testData.expectedHtmlArgs), Got: \(htmlArgs)")
    }
}

// MARK: - Extensions

/// Extension to add count property to XcovArgumentCollection for testing
extension XcovArgumentCollection {
    var count: Int {
        return self.arguments.count
    }
}
