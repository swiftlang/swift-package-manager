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
import Commands

import _InternalTestSupport

enum ParsingTestCategory {
    case basic
    case complexFilePath
    case edgeCase
    case realWorldScenario
}

struct ParsingTestData {
    let category: ParsingTestCategory
    let argumentUT: String
    let expectedFormat: CoverageFormat?
    let expectedValue: String
}

struct GetArgumentsTestData {
    let argumentUT: String
    let formatUT: CoverageFormat
    let expectedValue: [String]
}

@Suite(
    .tags(
        .TestSize.small,
        .Feature.CodeCoverage,
    ),
)
struct XcovArgumentTests {
    static let longString = String(repeating: "very/long/path/", count: 100) + "file"
    @Test(
        arguments: [
            ParsingTestData(
                category: .basic,
                argumentUT: "output.json",
                expectedFormat: nil,
                expectedValue: "output.json",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "json=output.json",
                expectedFormat: .json,
                expectedValue: "output.json",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "html=/path/to/coverage.html",
                expectedFormat: .html,
                expectedValue: "/path/to/coverage.html",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "xml=output.xml",
                expectedFormat: nil,
                expectedValue: "xml=output.xml",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "--title",
                expectedFormat: nil,
                expectedValue: "--title",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "\"My title\"",
                expectedFormat: nil,
                expectedValue: "\"My title\"",
            ),
            ParsingTestData(
                category: .basic,
                argumentUT: "--coverage-watermark=80,20",
                expectedFormat: nil,
                expectedValue: "--coverage-watermark=80,20",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "",
                expectedFormat: nil,
                expectedValue: "",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "=",
                expectedFormat: nil,
                expectedValue: "=",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "json=",
                expectedFormat: .json,
                expectedValue: "",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "json=key=value=extra",
                expectedFormat: .json,
                expectedValue: "key=value=extra",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "unknownformat=",
                expectedFormat: nil,
                expectedValue: "unknownformat=",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "JSON=output.json",
                expectedFormat: nil,
                expectedValue: "JSON=output.json",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "Html=output.html",
                expectedFormat: nil,
                expectedValue: "Html=output.html",
            ),
            ParsingTestData(
                category: .edgeCase,
                argumentUT: "json=\(Self.longString)",
                expectedFormat: .json,
                expectedValue: Self.longString,
            ),
            ParsingTestData(
                category: .complexFilePath,
                argumentUT: "json=/path/with spaces/file.json",
                expectedFormat: .json,
                expectedValue: "/path/with spaces/file.json",
            ),
            ParsingTestData(
                category: .complexFilePath,
                argumentUT: "html=/path/with-dashes/file.html",
                expectedFormat: .html,
                expectedValue: "/path/with-dashes/file.html",
            ),
            ParsingTestData(
                category: .complexFilePath,
                argumentUT: "json=/path/with.dots/file.json",
                expectedFormat: .json,
                expectedValue: "/path/with.dots/file.json",
            ),
            ParsingTestData(
                category: .complexFilePath,
                argumentUT: "html=/path/with_underscores/file.html",
                expectedFormat: .html,
                expectedValue: "/path/with_underscores/file.html",
            ),
            ParsingTestData(
                // Unsupported format with unicode
                category: .complexFilePath,
                argumentUT: "lcov=/path/with/unicode/файл.lcov",
                expectedFormat: nil,
                expectedValue: "lcov=/path/with/unicode/файл.lcov",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "json=coverage.json",
                expectedFormat: .json,
                expectedValue: "coverage.json",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "json=./coverage/coverage.json",
                expectedFormat: .json,
                expectedValue: "./coverage/coverage.json",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "json=/tmp/build/coverage.json",
                expectedFormat: .json,
                expectedValue: "/tmp/build/coverage.json",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "json=~/Desktop/coverage.json",
                expectedFormat: .json,
                expectedValue: "~/Desktop/coverage.json",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "json=./build/Debug/coverage.json",
                expectedFormat: .json,
                expectedValue: "./build/Debug/coverage.json",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=coverage-report",
                expectedFormat: .html,
                expectedValue: "coverage-report",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=./coverage/html-report",
                expectedFormat: .html,
                expectedValue: "./coverage/html-report",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=/tmp/build/coverage-html",
                expectedFormat: .html,
                expectedValue: "/tmp/build/coverage-html",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=~/Desktop/coverage-report",
                expectedFormat: .html,
                expectedValue: "~/Desktop/coverage-report",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=./build/Debug/coverage-html",
                expectedFormat: .html,
                expectedValue: "./build/Debug/coverage-html",
            ),

            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "lcov=coverage.lcov",
                expectedFormat: nil,
                expectedValue: "lcov=coverage.lcov",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "xml=coverage.xml",
                expectedFormat: nil,
                expectedValue: "xml=coverage.xml",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "cobertura=coverage.xml",
                expectedFormat: nil,
                expectedValue: "cobertura=coverage.xml",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "gcov=coverage.gcov",
                expectedFormat: nil,
                expectedValue: "gcov=coverage.gcov",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "jacoco=coverage.xml",
                expectedFormat: nil,
                expectedValue: "jacoco=coverage.xml",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=--coverage-watermark=80,20",
                expectedFormat: .html,
                expectedValue: "--coverage-watermark=80,20",
            ),
            ParsingTestData(
                category: .realWorldScenario,
                argumentUT: "html=--title=\"my title\"",
                expectedFormat: .html,
                expectedValue: "--title=\"my title\"",
            ),
        ],
    )
    func parsingArgumentReturnsExpectedValue(
        testData: ParsingTestData,
    ) throws {
        let argument = XcovArgument(argument: testData.argumentUT)
        let result = try #require(argument, "Failed to parse complex path: \(testData.argumentUT)")

        #expect(result.format == testData.expectedFormat)
        #expect(result.value == testData.expectedValue)
    }

    @Test(
        arguments: [
            GetArgumentsTestData(
                argumentUT: "json=output.json",
                formatUT: .json,
                expectedValue: ["output.json"],
            ),
            GetArgumentsTestData(
                argumentUT: "json=",
                formatUT: .json,
                expectedValue: [""],
            ),
            GetArgumentsTestData(
                argumentUT: "json=output.json",
                formatUT: .html,
                expectedValue: [],
            ),
        ] + CoverageFormat.allCases.map { format in
            [
                GetArgumentsTestData(
                    argumentUT: "xml=output.xml",
                    formatUT: format,
                    expectedValue: ["xml=output.xml"],
                ),
                GetArgumentsTestData(
                    argumentUT: "output.json",
                    formatUT: format,
                    expectedValue: ["output.json"],
                ),
            ]
        }.reduce([], +),
    )
    func getGetArgumentsReturnsExpectedValue(
        testData: GetArgumentsTestData,
    ) async throws {
        let argument = try #require(XcovArgument(argument: testData.argumentUT))

        let result = argument.getArguments(for: testData.formatUT)

        #expect(result == testData.expectedValue)

    }

}

@Suite
struct XcovArgumentCollectionTests {
    @Suite
    struct BasicTests {

        @Test("Collection preserves order of arguments")
        func collectionPreservesOrder() throws {
            // Given: Multiple -Xcov arguments in specific order
            let arg1 = try #require(XcovArgument(argument: "json=first.json"))
            let arg2 = try #require(XcovArgument(argument: "json=second.json"))
            let arg3 = try #require(XcovArgument(argument: "json=third.json"))

            let collection = XcovArgumentCollection([arg1, arg2, arg3])

            // When: Getting arguments for json format
            let result = collection.getArguments(for: .json)

            // Then: Should preserve the order
            #expect(result == ["first.json", "second.json", "third.json"])
        }

        @Test("Collection filters by format correctly")
        func collectionFiltersByFormat() throws {
            // Given: Mixed format -Xcov arguments
            let jsonArg1 = try #require(XcovArgument(argument: "json=output1.json"))
            let htmlArg = try #require(XcovArgument(argument: "html=output.html"))
            let jsonArg2 = try #require(XcovArgument(argument: "json=output2.json"))
            let unsupportedArg = try #require(XcovArgument(argument: "xml=output.xml"))

            let collection = XcovArgumentCollection([jsonArg1, htmlArg, jsonArg2, unsupportedArg])

            // When: Getting arguments for json format
            let jsonResult = collection.getArguments(for: .json)

            // Then: Should return only json values plus unsupported format values
            #expect(jsonResult == ["output1.json", "output2.json", "xml=output.xml"])

            // When: Getting arguments for html format
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should return only html values plus unsupported format values
            #expect(htmlResult == ["output.html", "xml=output.xml"])
        }

        @Test("Empty collection returns empty results")
        func emptyCollectionReturnsEmptyResults() throws {
            // Given: Empty collection
            let collection = XcovArgumentCollection([])

            // When: Getting arguments for any format
            let jsonResult = collection.getArguments(for: .json)
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should return empty arrays
            #expect(jsonResult.isEmpty)
            #expect(htmlResult.isEmpty)
        }

        @Test("Collection with only unsupported formats")
        func collectionWithOnlyUnsupportedFormats() throws {
            // Given: Collection with only unsupported formats
            let arg1 = try #require(XcovArgument(argument: "xml=file1.xml"))
            let arg2 = try #require(XcovArgument(argument: "lcov=file2.lcov"))
            let arg3 = try #require(XcovArgument(argument: "cobertura=file3.xml"))

            let collection = XcovArgumentCollection([arg1, arg2, arg3])

            // When: Getting arguments for supported formats
            let jsonResult = collection.getArguments(for: .json)
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should return all unsupported format values
            #expect(jsonResult == ["xml=file1.xml", "lcov=file2.lcov", "cobertura=file3.xml"])
            #expect(htmlResult == ["xml=file1.xml", "lcov=file2.lcov", "cobertura=file3.xml"])
        }
    }

    @Suite("XcovArgumentCollection Complex Order Tests")
    struct ComplexOrderTests {

        @Test("Collection preserves order with mixed formats and unsupported")
        func collectionPreservesOrderWithMixedFormats() throws {
            // Given: Complex mix of arguments in specific order
            let args = [
                try #require(XcovArgument(argument: "json=first.json")),
                try #require(XcovArgument(argument: "xml=unsupported1.xml")),
                try #require(XcovArgument(argument: "html=first.html")),
                try #require(XcovArgument(argument: "json=second.json")),
                try #require(XcovArgument(argument: "plain.txt")),  // No format
                try #require(XcovArgument(argument: "lcov=unsupported2.lcov")),
                try #require(XcovArgument(argument: "html=second.html"))
            ]

            let collection = XcovArgumentCollection(args)

            // When: Getting arguments for json format
            let jsonResult = collection.getArguments(for: .json)

            // Then: Should preserve order and include unsupported formats
            #expect(jsonResult == [
                "first.json",           // json format
                "xml=unsupported1.xml", // unsupported format
                "second.json",          // json format
                "plain.txt",            // no format specified
                "lcov=unsupported2.lcov" // unsupported format
            ])

            // When: Getting arguments for html format
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should preserve order and include unsupported formats
            #expect(htmlResult == [
                "xml=unsupported1.xml", // unsupported format
                "first.html",           // html format
                "plain.txt",            // no format specified
                "lcov=unsupported2.lcov", // unsupported format
                "second.html"           // html format
            ])
        }

        @Test("Collection handles duplicate values correctly")
        func collectionHandlesDuplicateValues() throws {
            // Given: Arguments with duplicate values
            let args = [
                try #require(XcovArgument(argument: "json=output.json")),
                try #require(XcovArgument(argument: "html=output.json")), // Same filename, different format
                try #require(XcovArgument(argument: "json=output.json")),  // Exact duplicate
                try #require(XcovArgument(argument: "xml=output.json"))    // Same filename, unsupported format
            ]

            let collection = XcovArgumentCollection(args)

            // When: Getting arguments for json format
            let jsonResult = collection.getArguments(for: .json)

            // Then: Should include duplicates and unsupported
            #expect(jsonResult == ["output.json", "output.json", "xml=output.json"])

            // When: Getting arguments for html format
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should include duplicates and unsupported
            #expect(htmlResult == ["output.json", "xml=output.json"])
        }

        @Test("Collection with interspersed no-format arguments")
        func collectionWithInterspersedNoFormatArguments() throws {
            // Given: Arguments with no format interspersed with formatted ones
            let args = [
                try #require(XcovArgument(argument: "first.json")),     // No format
                try #require(XcovArgument(argument: "json=second.json")),
                try #require(XcovArgument(argument: "third.html")),     // No format
                try #require(XcovArgument(argument: "html=fourth.html")),
                try #require(XcovArgument(argument: "fifth.xml"))       // No format
            ]

            let collection = XcovArgumentCollection(args)

            // When: Getting arguments for json format
            let jsonResult = collection.getArguments(for: .json)

            // Then: Should include no-format arguments and matching format
            #expect(jsonResult == [
                "first.json",    // no format
                "second.json",   // json format
                "third.html",    // no format
                "fifth.xml"      // no format
            ])

            // When: Getting arguments for html format
            let htmlResult = collection.getArguments(for: .html)

            // Then: Should include no-format arguments and matching format
            #expect(htmlResult == [
                "first.json",    // no format
                "third.html",    // no format
                "fourth.html",   // html format
                "fifth.xml"      // no format
            ])
        }
    }

    @Test
    func mixedRealWorldScenario() throws {
        // Given: A realistic mix of arguments from a command line
        let args = [
            try #require(XcovArgument(argument: "json=./coverage/coverage.json")),
            try #require(XcovArgument(argument: "html=./coverage/html-report")),
            try #require(XcovArgument(argument: "lcov=./coverage/lcov.info")),  // Unsupported
            try #require(XcovArgument(argument: "./coverage/summary.txt")),     // No format
            try #require(XcovArgument(argument: "xml=./coverage/cobertura.xml")), // Unsupported
            try #require(XcovArgument(argument: "html=--coverage-watermark=80,20")),
            try #require(XcovArgument(argument: "html=--title=\"my title\"")),

        ]

        let collection = XcovArgumentCollection(args)

        // When: Getting JSON format arguments
        let jsonResult = collection.getArguments(for: .json)
        #expect(jsonResult == [
            "./coverage/coverage.json",    // json format
            "lcov=./coverage/lcov.info",   // unsupported
            "./coverage/summary.txt",      // no format
            "xml=./coverage/cobertura.xml", // unsupported
        ])

        // When: Getting HTML format arguments
        let htmlResult = collection.getArguments(for: .html)
        #expect(htmlResult == [
            "./coverage/html-report",     // html format
            "lcov=./coverage/lcov.info",  // unsupported
            "./coverage/summary.txt",     // no format
            "xml=./coverage/cobertura.xml", // unsupported
            "--coverage-watermark=80,20",
            "--title=\"my title\"",
        ])
    }

}
