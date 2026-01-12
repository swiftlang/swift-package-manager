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
                try #require(XcovArgument(argument: "xml=./coverage/cobertura.xml")) // Unsupported
            ]

            let collection = XcovArgumentCollection(args)

            // When: Getting JSON format arguments
            let jsonResult = collection.getArguments(for: .json)
            #expect(jsonResult == [
                "./coverage/coverage.json",    // json format
                "lcov=./coverage/lcov.info",   // unsupported
                "./coverage/summary.txt",      // no format
                "xml=./coverage/cobertura.xml" // unsupported
            ])

            // When: Getting HTML format arguments
            let htmlResult = collection.getArguments(for: .html)
            #expect(htmlResult == [
                "./coverage/html-report",     // html format
                "lcov=./coverage/lcov.info",  // unsupported
                "./coverage/summary.txt",     // no format
                "xml=./coverage/cobertura.xml" // unsupported
            ])
        }

    }
}


@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct XcovArgumentTestsBasicParsing {

    // @Test("Parse simple value without format")
    // func parseSimpleValue() throws {
    //     // Given: A simple value argument
    //     let argumentString = "output.json"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should successfully parse with no format and the value
    //     let result = try #require(argument, "Failed to parse simple value")
    //     #expect(result.format == nil)
    //     #expect(result.value == "output.json")
    // }

    // @Test("Parse argument with supported coverage format")
    // func parseArgumentWithSupportedFormat() throws {
    //     // Given: An argument with a supported coverage format
    //     let argumentString = "json=output.json"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should successfully parse with correct format and value
    //     let result = try #require(argument, "Failed to parse format=value syntax")
    //     #expect(result.format == .json)
    //     #expect(result.value == "output.json")
    // }

    // @Test("Parse argument with HTML format")
    // func parseArgumentWithHTMLFormat() throws {
    //     // Given: An argument with HTML coverage format
    //     let argumentString = "html=/path/to/coverage.html"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should successfully parse with correct format and value
    //     let result = try #require(argument, "Failed to parse html format")
    //     #expect(result.format == .html)
    //     #expect(result.value == "/path/to/coverage.html")
    // }

    // @Test("Parse argument with unsupported coverage format")
    // func parseArgumentWithUnsupportedFormat() throws {
    //     // Given: An argument with an unsupported coverage format
    //     let argumentString = "xml=output.xml"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should successfully parse with nil format and full value
    //     let result = try #require(argument, "Failed to parse unsupported format")
    //     #expect(result.format == nil)
    //     #expect(result.value == "xml=output.xml")
    // }
}

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct XcovArgumentEdgeCaseParsingTests {

    // @Test("Parse empty string")
    // func parseEmptyString() throws {
    //     // Given: An empty string argument
    //     let argumentString = ""

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should successfully parse with no format and empty value
    //     let result = try #require(argument, "Failed to parse empty string")
    //     #expect(result.format == nil)
    //     #expect(result.value == "")
    // }

    // @Test("Parse format with empty value")
    // func parseFormatWithEmptyValue() throws {
    //     // Given: A format with empty value
    //     let argumentString = "json="

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should parse with format but empty value
    //     let result = try #require(argument, "Failed to parse format with empty value")
    //     #expect(result.format == .json)
    //     #expect(result.value == "")
    // }

    // @Test("Parse value with multiple equals signs")
    // func parseValueWithMultipleEqualsigns() throws {
    //     // Given: A value containing multiple equals signs
    //     let argumentString = "json=key=value=extra"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should parse format correctly and keep remaining equals in value
    //     let result = try #require(argument, "Failed to parse multiple equals")
    //     #expect(result.format == .json)
    //     #expect(result.value == "key=value=extra")
    // }

    // @Test("Parse equals sign only")
    // func parseEqualsSignOnly() throws {
    //     // Given: Just an equals sign
    //     let argumentString = "="

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should parse as unsupported format (empty format name)
    //     let result = try #require(argument, "Failed to parse equals only")
    //     #expect(result.format == nil)
    //     #expect(result.value == "=")
    // }

    // @Test("Parse format name only with equals")
    // func parseFormatNameOnlyWithEquals() throws {
    //     // Given: Format name followed by equals but no value
    //     let argumentString = "unknownformat="

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should parse as unsupported format with full string as value
    //     let result = try #require(argument, "Failed to parse unknown format with equals")
    //     #expect(result.format == nil)
    //     #expect(result.value == "unknownformat=")
    // }

    // @Test("Parse case sensitivity")
    // func parseCaseSensitivity() throws {
    //     // Given: Format names with different cases
    //     let upperCaseArg = "JSON=output.json"
    //     let mixedCaseArg = "Html=output.html"

    //     // When: Parsing the arguments
    //     let upperResult = XcovArgument(argument: upperCaseArg)
    //     let mixedResult = XcovArgument(argument: mixedCaseArg)

    //     // Then: Should be case-sensitive and treat as unsupported
    //     let upperParsed = try #require(upperResult, "Failed to parse uppercase")
    //     let mixedParsed = try #require(mixedResult, "Failed to parse mixed case")

    //     #expect(upperParsed.format == nil)
    //     #expect(upperParsed.value == "JSON=output.json")
    //     #expect(mixedParsed.format == nil)
    //     #expect(mixedParsed.value == "Html=output.html")
    // }

    // @Test("Parse very long values")
    // func parseVeryLongValues() throws {
    //     // Given: Very long file path
    //     let longPath = String(repeating: "very/long/path/", count: 100) + "file.json"
    //     let argumentString = "json=\(longPath)"

    //     // When: Parsing the argument
    //     let argument = XcovArgument(argument: argumentString)

    //     // Then: Should handle long values correctly
    //     let result = try #require(argument, "Failed to parse long path")
    //     #expect(result.format == .json)
    //     #expect(result.value == longPath)
    // }
}

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct XcovArgumentGetArgumentsTests {

    // @Test("getArguments returns value for matching format")
    // func getArgumentsReturnsValueForMatchingFormat() throws {
    //     // Given: A -Xcov argument with json format
    //     let argument = try #require(XcovArgument(argument: "json=output.json"))

    //     // When: Getting arguments for json format
    //     let result = argument.getArguments(for: .json)

    //     // Then: Should return the value
    //     #expect(result == ["output.json"])
    // }

    // @Test("getArguments returns empty for non-matching format")
    // func getArgumentsReturnsEmptyForNonMatchingFormat() throws {
    //     // Given: A -Xcov argument with json format
    //     let argument = try #require(XcovArgument(argument: "json=output.json"))

    //     // When: Getting arguments for html format
    //     let result = argument.getArguments(for: .html)

    //     // Then: Should return empty array
    //     #expect(result.isEmpty)
    // }

    // @Test("getArguments returns value for unsupported format")
    // func getArgumentsReturnsValueForUnsupportedFormat() throws {
    //     // Given: A -Xcov argument with unsupported format
    //     let argument = try #require(XcovArgument(argument: "xml=output.xml"))

    //     // When: Getting arguments for any format
    //     let jsonResult = argument.getArguments(for: .json)
    //     let htmlResult = argument.getArguments(for: .html)

    //     // Then: Should return the full value for any format (unsupported)
    //     #expect(jsonResult == ["xml=output.xml"])
    //     #expect(htmlResult == ["xml=output.xml"])
    // }

    // @Test("getArguments with no format specified")
    // func getArgumentsWithNoFormatSpecified() throws {
    //     // Given: A -Xcov argument without format
    //     let argument = try #require(XcovArgument(argument: "output.json"))

    //     // When: Getting arguments for any format
    //     let jsonResult = argument.getArguments(for: .json)
    //     let htmlResult = argument.getArguments(for: .html)

    //     // Then: Should return the value for any format (no format specified)
    //     #expect(jsonResult == ["output.json"])
    //     #expect(htmlResult == ["output.json"])
    // }

    // @Test("getArguments with empty value")
    // func getArgumentsWithEmptyValue() throws {
    //     // Given: A -Xcov argument with empty value
    //     let argument = try #require(XcovArgument(argument: "json="))

    //     // When: Getting arguments for json format
    //     let result = argument.getArguments(for: .json)

    //     // Then: Should return empty string
    //     #expect(result == [""])
    // }
}

// @Suite(
//     .tags(
//         .TestSize.small,
//     ),
// )
// struct XcovArgumentCollectiontests {

// }
@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct XcovArgumentRealWorldScenariosTests {

    // @Test("Typical JSON coverage output scenarios")
    // func typicalJSONScenarios() throws {
    //     let scenarios = [
    //         "json=coverage.json",
    //         "json=./coverage/coverage.json",
    //         "json=/tmp/build/coverage.json",
    //         "json=~/Desktop/coverage.json",
    //         "json=./build/Debug/coverage.json"
    //     ]

    //     for scenario in scenarios {
    //         let argument = try #require(XcovArgument(argument: scenario))
    //         #expect(argument.format == .json)
    //         #expect(argument.value == String(scenario.dropFirst(5)))
    //     }
    // }

    // @Test("Typical HTML coverage output scenarios")
    // func typicalHTMLScenarios() throws {
    //     let scenarios = [
    //         "html=coverage-report",
    //         "html=./coverage/html-report",
    //         "html=/tmp/build/coverage-html",
    //         "html=~/Desktop/coverage-report",
    //         "html=./build/Debug/coverage-html"
    //     ]

    //     for scenario in scenarios {
    //         let argument = try #require(XcovArgument(argument: scenario))
    //         #expect(argument.format == .html)
    //         #expect(argument.value == String(scenario.dropFirst(5)))
    //     }
    // }

    // @Test(
    //     arguments: CoverageFormat.allCases, [
    //         "lcov=coverage.lcov",
    //         "xml=coverage.xml",
    //         "cobertura=coverage.xml",
    //         "gcov=coverage.gcov",
    //         "jacoco=coverage.xml"
    //     ]
    // )
    // func unsupportedCommonFormats(
    //     coverageFormatUT: CoverageFormat, argumentUT: String,
    // ) throws {
    //     // let scenarios = [
    //     //     "lcov=coverage.lcov",
    //     //     "xml=coverage.xml",
    //     //     "cobertura=coverage.xml",
    //     //     "gcov=coverage.gcov",
    //     //     "jacoco=coverage.xml"
    //     // ]

    //     // for scenario in scenarios {
    //     //     let argument = try #require(XcovArgument(argument: scenario))
    //     //     #expect(argument.format == nil)
    //     //     #expect(argument.value == scenario)

    //     //     // Should be returned for any format query
    //     //     #expect(argument.getArguments(for: .json) == [scenario])
    //     //     #expect(argument.getArguments(for: .html) == [scenario])
    //     // }
    //     let argument = try #require(XcovArgument(argument: argumentUT))

    //     #expect(argument.format == nil)
    //     #expect(argument.value == argumentUT)
    //     #expect(argument.getArguments(for: coverageFormatUT) == [argumentUT])
    // }

    // @Test("Mixed real-world command line scenario")
    // func mixedRealWorldScenario() throws {
    //     // Given: A realistic mix of arguments from a command line
    //     let args = [
    //         try #require(XcovArgument(argument: "json=./coverage/coverage.json")),
    //         try #require(XcovArgument(argument: "html=./coverage/html-report")),
    //         try #require(XcovArgument(argument: "lcov=./coverage/lcov.info")),  // Unsupported
    //         try #require(XcovArgument(argument: "./coverage/summary.txt")),     // No format
    //         try #require(XcovArgument(argument: "xml=./coverage/cobertura.xml")) // Unsupported
    //     ]

    //     let collection = XcovArgumentCollection(args)

    //     // When: Getting JSON format arguments
    //     let jsonResult = collection.getArguments(for: .json)
    //     #expect(jsonResult == [
    //         "./coverage/coverage.json",    // json format
    //         "lcov=./coverage/lcov.info",   // unsupported
    //         "./coverage/summary.txt",      // no format
    //         "xml=./coverage/cobertura.xml" // unsupported
    //     ])

    //     // When: Getting HTML format arguments
    //     let htmlResult = collection.getArguments(for: .html)
    //     #expect(htmlResult == [
    //         "./coverage/html-report",     // html format
    //         "lcov=./coverage/lcov.info",  // unsupported
    //         "./coverage/summary.txt",     // no format
    //         "xml=./coverage/cobertura.xml" // unsupported
    //     ])
    // }
}
