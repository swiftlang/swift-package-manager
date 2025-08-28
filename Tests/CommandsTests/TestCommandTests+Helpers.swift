//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

import struct Basics.AbsolutePath
import struct Basics.RelativePath
import func Commands.getOutputDir
import enum Commands.CoverageFormat
import struct Commands.CoverageFormatOutput
import typealias Basics.StringError
import struct Commands.PlainTextEncoder

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct TestCommmandHelpersTests {

    @Suite
    struct getOutputDirTests {
        @Test(
            arguments: [
                "",
                """
                line1
                """,
                """
                line1
                line2
                """,
                """
                line1
                line2
                line3
                """,
            ]
        )
        func outputDirArgumentNotPresentReturnsNil(
            content: String
        ) async throws {
            let actual = try getOutputDir(from: content, workspacePath: AbsolutePath.root,)

            #expect(actual == nil)
        }

        struct GetOutputDirTestData: Identifiable {
            let content: String
            let expected: AbsolutePath?
            let id: String
        }

        @Test(
            arguments: [
                "=",
                "\n",
                " ",
                "  ",
                "    ",
            ].map { sep in
                return [
                    GetOutputDirTestData(
                        content: """
                            --output-dir\(sep)/Bar/baz
                            """,
                        expected: AbsolutePath("/Bar/baz"),
                        id: "Single argument with seperator '\(sep)'",
                    ),
                    GetOutputDirTestData(
                        content: """
                            --output-dir\(sep)/Bar/baz
                            --output-dir\(sep)/this/should/win
                            """,
                        expected: AbsolutePath("/this/should/win"),
                        id: "Two output dir arguments with seperator '\(sep)' returns the last occurrence",
                    ),
                    GetOutputDirTestData(
                        content: """
                            --output-dir\(sep)/Bar/baz
                            --output-dir\(sep)/what
                            --output-dir\(sep)/this/should/win
                            """,
                        expected: AbsolutePath("/this/should/win"),
                        id: "three output dir arguments with seperator '\(sep)' returns the last occurrence",
                    ),
                    GetOutputDirTestData(
                        content: """
                            prefix
                            --output-dir\(sep)/Bar/baz
                            """,
                        expected: AbsolutePath("/Bar/baz"),
                        id: "seperator '\(sep)': with content prefix",
                    ),
                    GetOutputDirTestData(
                        content: """
                            --output-dir\(sep)/Bar/baz
                            suffix
                            """,
                        expected: AbsolutePath("/Bar/baz"),
                        id: "seperator '\(sep)': with content suffix",
                    ),
                    GetOutputDirTestData(
                        content: """
                            line_prefix
                            --output-dir\(sep)/Bar/baz
                            suffix
                            """,
                        expected: AbsolutePath("/Bar/baz"),
                        id: "seperator '\(sep)': with line content and suffix",
                    ),
                    GetOutputDirTestData(
                        content: """
                            prefix--output-dir\(sep)/Bar/baz
                            """,
                        expected: nil,
                        id: "seperator '\(sep)': with line prefix (no space)",
                    ),
                    GetOutputDirTestData(
                        content: """
                            prefix --output-dir\(sep)/Bar/baz
                            """,
                        expected: AbsolutePath("/Bar/baz"),
                        id: "seperator '\(sep)': with line prefix (which contains a space)",
                    ),
                ]
            }.flatMap { $0 },
        )
        func contentContainsOutputDirectoryReturnsCorrectPath(
            data: GetOutputDirTestData,
        ) async throws {
            let actual = try getOutputDir(from: data.content, workspacePath: AbsolutePath.root,)

            #expect(actual == data.expected)
        }

        @Test(
            arguments: [
                (
                    relativePathUnderTest: "./relative/path",
                    dir: AbsolutePath("/some/random/longish/path"),
                    expected: AbsolutePath("/some/random/longish/path/relative/path"),
                ),
                (
                    relativePathUnderTest: "relative/path",
                    dir: AbsolutePath("/some/random/longish/path"),
                    expected: AbsolutePath("/some/random/longish/path/relative/path"),
                ),
                (
                    relativePathUnderTest: "../relative/path",
                    dir: AbsolutePath("/some/random/longish/path"),
                    expected: AbsolutePath("/some/random/longish/relative/path"),
                ),
                (
                    relativePathUnderTest: "../../relative/path",
                    dir: AbsolutePath("/some/random/longish/path"),
                    expected: AbsolutePath("/some/random/relative/path"),
                ),
            ],
        )
        func contentContainsOutputDirectoryAsRelativePathReturnsCorrectPath(
            relativePathUnderTest: String,
            dir: AbsolutePath,
            expected: AbsolutePath,
        ) async throws {
            let relativePathUnderTest = RelativePath(relativePathUnderTest)
            let content = """
            --output-dir \(relativePathUnderTest)
            """

            let actual = try getOutputDir(from: content, workspacePath: dir,)

            #expect(actual == expected)
        }

        @Test func sample() async throws {
            let logMessage = "ERROR: User 'john.doe' failed login attempt from IP 192.168.1.100."

            // Create a Regex with named captue groups for user and ipAddress
            let regex = try! Regex("User '(?<user>[a-zA-Z0-9.]+)' failed login attempt from IP (?<ipAddress>\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})")

            // Find the first match in the log message
            if let match = logMessage.firstMatch(of: regex) {
                // Access the captured values using their named properties
                // let username = match.user
                // let ipAddress = match.ipAddress

                #expect(Bool(true))
            } else {
                #expect(Bool(false))
            }
        }
    }

    @Suite
    struct CoverageFormatOutputTests {

        var validData: [CoverageFormat: AbsolutePath] {
            [
                CoverageFormat.json: AbsolutePath("/some/path/json"),
                CoverageFormat.html: AbsolutePath("/some/path/html"),
            ]
        }

        // MARK: - Initialization Tests

        @Test
        func initEmpty() async throws {
            let output = CoverageFormatOutput()
            #expect(output.formats.isEmpty)
        }

        @Test
        func initWithData() async throws {
            let output = CoverageFormatOutput(data: validData)
            #expect(output.formats.count == 2)
            #expect(output.formats.contains(CoverageFormat.json))
            #expect(output.formats.contains(CoverageFormat.html))
        }

        // MARK: - addFormat Tests

        @Test
        func addFormatSuccess() async throws {
            var output = CoverageFormatOutput()
            let jsonPath = AbsolutePath("/path/to/json")

            try output.addFormat(CoverageFormat.json, path: jsonPath)

            #expect(output.formats.count == 1)
            #expect(output.formats.contains(CoverageFormat.json))
            #expect(output[CoverageFormat.json] == jsonPath)
        }

        @Test
        func addFormatMultiple() async throws {
            var output = CoverageFormatOutput()
            let jsonPath = AbsolutePath("/path/to/json")
            let htmlPath = AbsolutePath("/path/to/html")

            try output.addFormat(CoverageFormat.json, path: jsonPath)
            try output.addFormat(CoverageFormat.html, path: htmlPath)

            #expect(output.formats.count == 2)
            #expect(output.formats.contains(CoverageFormat.json))
            #expect(output.formats.contains(CoverageFormat.html))
            #expect(output[CoverageFormat.json] == jsonPath)
            #expect(output[CoverageFormat.html] == htmlPath)
        }

        @Test
        func addFormatDuplicateThrowsError() async throws {
            var output = CoverageFormatOutput()
            let jsonPath1 = AbsolutePath("/path/to/json1")
            let jsonPath2 = AbsolutePath("/path/to/json2")

            try output.addFormat(CoverageFormat.json, path: jsonPath1)

            #expect(throws: StringError("Coverage format 'json' already exists")) {
                try output.addFormat(CoverageFormat.json, path: jsonPath2)
            }

            // Verify original path is unchanged
            #expect(output[CoverageFormat.json] == jsonPath1)
            #expect(output.formats.count == 1)
        }

        // MARK: - Subscript Tests

        @Test
        func subscriptExistingFormat() async throws {
            let output = CoverageFormatOutput(data: validData)

            #expect(output[CoverageFormat.json] == AbsolutePath("/some/path/json"))
            #expect(output[CoverageFormat.html] == AbsolutePath("/some/path/html"))
        }

        @Test
        func subscriptNonExistentFormat() async throws {
            let output = CoverageFormatOutput()

            #expect(output[CoverageFormat.json] == nil)
            #expect(output[CoverageFormat.html] == nil)
        }

        // MARK: - getPath Tests

        @Test
        func getPathExistingFormat() async throws {
            let output = CoverageFormatOutput(data: validData)

            let jsonPath = try output.getPath(for: CoverageFormat.json)
            let htmlPath = try output.getPath(for: CoverageFormat.html)

            #expect(jsonPath == AbsolutePath("/some/path/json"))
            #expect(htmlPath == AbsolutePath("/some/path/html"))
        }

        @Test
        func getPathNonExistentFormatThrowsError() async throws {
            let output = CoverageFormatOutput()

            #expect(throws: StringError("Missing coverage format output path for 'json'")) {
                try output.getPath(for: CoverageFormat.json)
            }

            #expect(throws: StringError("Missing coverage format output path for 'html'")) {
                try output.getPath(for: CoverageFormat.html)
            }
        }

        // MARK: - formats Property Tests

        @Test
        func formatsEmptyWhenNoData() async throws {
            let output = CoverageFormatOutput()
            #expect(output.formats.isEmpty)
        }

        @Test
        func formatsReturnsSortedFormats() async throws {
            let output = CoverageFormatOutput(data: validData)
            let formats = output.formats

            #expect(formats.count == 2)
            // Formats should be sorted alphabetically by raw value
            #expect(formats == [CoverageFormat.html, CoverageFormat.json])  // html comes before json alphabetically
        }

        @Test
        func formatsAfterAddingFormats() async throws {
            var output = CoverageFormatOutput()

            try output.addFormat(CoverageFormat.json, path: AbsolutePath("/json/path"))
            #expect(output.formats == [CoverageFormat.json])

            try output.addFormat(CoverageFormat.html, path: AbsolutePath("/html/path"))
            #expect(output.formats == [CoverageFormat.html, CoverageFormat.json])  // sorted
        }

        // MARK: - forEach Tests

        @Test
        func forEachEmptyOutput() async throws {
            let output = CoverageFormatOutput()
            var iterationCount = 0

            output.forEach { format, path in
                iterationCount += 1
            }

            #expect(iterationCount == 0)
        }

        @Test
        func forEachWithData() async throws {
            let output = CoverageFormatOutput(data: validData)
            var results: [CoverageFormat: AbsolutePath] = [:]

            output.forEach { format, path in
                results[format] = path
            }

            #expect(results.count == 2)
            #expect(results[CoverageFormat.json] == AbsolutePath("/some/path/json"))
            #expect(results[CoverageFormat.html] == AbsolutePath("/some/path/html"))
        }

        @Test
        func forEachCanThrow() async throws {
            let output = CoverageFormatOutput(data: validData)

            struct TestError: Error, Equatable {
                let message: String
            }

            #expect(throws: TestError(message: "test error")) {
                try output.forEach { format, path in
                    if format == CoverageFormat.json {
                        throw TestError(message: "test error")
                    }
                }
            }
        }

        // MARK: - Integration Tests

        @Test
        func completeWorkflow() async throws {
            // Start with empty output
            var output = CoverageFormatOutput()
            #expect(output.formats.isEmpty)

            // Add first format
            let jsonPath = AbsolutePath("/coverage/reports/coverage.json")
            try output.addFormat(CoverageFormat.json, path: jsonPath)
            #expect(output.formats == [CoverageFormat.json])
            #expect(output[CoverageFormat.json] == jsonPath)
            let actualJsonPath = try output.getPath(for: CoverageFormat.json)
            #expect(actualJsonPath == jsonPath)

            // Add second format
            let htmlPath = AbsolutePath("/coverage/reports/html")
            try output.addFormat(CoverageFormat.html, path: htmlPath)
            #expect(output.formats == [CoverageFormat.html, CoverageFormat.json])  // sorted
            #expect(output[CoverageFormat.html] == htmlPath)
            let actualHmtlPath = try output.getPath(for: CoverageFormat.html)
            #expect(actualHmtlPath == htmlPath)

            // Verify forEach works
            var collectedPaths: [CoverageFormat: AbsolutePath] = [:]
            output.forEach { format, path in
                collectedPaths[format] = path
            }
            #expect(collectedPaths.count == 2)
            #expect(collectedPaths[CoverageFormat.json] == jsonPath)
            #expect(collectedPaths[CoverageFormat.html] == htmlPath)

            // Verify duplicate add fails
            #expect(throws: StringError("Coverage format 'json' already exists")) {
                try output.addFormat(CoverageFormat.json, path: AbsolutePath("/different/path"))
            }

            // Verify original data is preserved
            #expect(output[CoverageFormat.json] == jsonPath)
            #expect(output.formats.count == 2)
        }

        // MARK: - Encoding Tests

        @Test("Encode as JSON with single format")
        func encodeAsJSONSingle() throws {
            let path = try AbsolutePath(validating: "/path/to/coverage.json")
            var output = CoverageFormatOutput()
            try output.addFormat(.json, path: path)

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let jsonData = try encoder.encode(output)
            let jsonString = String(decoding: jsonData, as: UTF8.self)
            let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

            #expect(decoded["json"] == "/path/to/coverage.json")
            #expect(decoded.count == 1)
        }

        @Suite(
            .tags(
                .TestSize.small,
                .Feature.Encoding,
            ),
        )
        struct EncodingTests {
            @Suite
            struct JsonEncodingTests {
                @Test("Encode as JSON with multiple formats")
                func encodeAsJSONMultiple() throws {
                    let jsonPath = try AbsolutePath(validating: "/path/to/coverage.json")
                    let htmlPath = try AbsolutePath(validating: "/path/to/coverage-html")

                    var output = CoverageFormatOutput()
                    try output.addFormat(.json, path: jsonPath)
                    try output.addFormat(.html, path: htmlPath)

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    encoder.outputFormatting = [.prettyPrinted]
                    let jsonData = try encoder.encode(output)
                    let jsonString = String(decoding: jsonData, as: UTF8.self)
                    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                    #expect(decoded["json"] == "/path/to/coverage.json")
                    #expect(decoded["html"] == "/path/to/coverage-html")
                    #expect(decoded.count == 2)

                    // Verify it's properly formatted JSON
                    #expect(jsonString.contains("{\n"))
                    #expect(jsonString.contains("\n}"))
                }

                @Test("Encode as JSON with empty data")
                func encodeAsJSONEmpty() throws {
                    let output = CoverageFormatOutput()

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    encoder.outputFormatting = [.prettyPrinted]
                    let jsonData = try encoder.encode(output)
                    let jsonString = String(decoding: jsonData, as: UTF8.self)
                    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                    #expect(decoded.isEmpty)
                    #expect(jsonString.contains("{\n\n}") || jsonString.contains("{}"))
                }
            }

            @Suite
            struct TextEncodingTests {
                @Test(
                    "Encode as text with single format",
                    arguments: CoverageFormat.allCases
                )
                func encodeAsTextSingle(
                    format: CoverageFormat,
                ) throws {
                    let path = try AbsolutePath(validating: "/path/to/coverage.json")
                    var output = CoverageFormatOutput()
                    try output.addFormat(format, path: path)

                    var encoder = PlainTextEncoder()
                    encoder.formattingOptions = [.prettyPrinted]
                    let textData = try encoder.encode(output)
                    let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                    // PlainTextEncoder capitalizes first letter of keys
                    let expectedFormat = format.rawValue.prefix(1).uppercased() + format.rawValue.dropFirst()
                    #expect(textString == "\(expectedFormat): /path/to/coverage.json")
                }

                @Test("Encode as text with multiple formats")
                func encodeAsTextMultiple() throws {
                    let jsonPath = try AbsolutePath(validating: "/path/to/coverage.json")
                    let htmlPath = try AbsolutePath(validating: "/path/to/coverage-html")

                    var output = CoverageFormatOutput()
                    try output.addFormat(.json, path: jsonPath)
                    try output.addFormat(.html, path: htmlPath)

                    var encoder = PlainTextEncoder()
                    encoder.formattingOptions = [.prettyPrinted]
                    let textData = try encoder.encode(output)
                    let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Should be sorted by format name (html comes before json alphabetically)
                    // PlainTextEncoder capitalizes first letter of keys
                    #expect(textString == "Html: /path/to/coverage-html\nJson: /path/to/coverage.json")
                }

                @Test("Encode as text with empty data")
                func encodeAsTextEmpty() throws {
                    let output = CoverageFormatOutput()

                    var encoder = PlainTextEncoder()
                    encoder.formattingOptions = [.prettyPrinted]
                    let textData = try encoder.encode(output)
                    let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                    #expect(textString.isEmpty)
                }
            }

            @Test("Encoding consistency - formats maintain sorting")
            func encodingConsistency() throws {
                // Add formats in reverse alphabetical order to test sorting
                let jsonPath = try AbsolutePath(validating: "/json/path")
                let htmlPath: AbsolutePath = try AbsolutePath(validating: "/html/path")

                var output = CoverageFormatOutput()
                try output.addFormat(.json, path: jsonPath)  // Add json first
                try output.addFormat(.html, path: htmlPath)  // Add html second

                // Text encoding should show html first (alphabetically)
                var textEncoder = PlainTextEncoder()
                textEncoder.formattingOptions = [.prettyPrinted]
                let textData = try textEncoder.encode(output)
                let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(textString.hasPrefix("Html:"))
                #expect(textString.hasSuffix("Json: /json/path"))

                // JSON encoding should also maintain consistent ordering
                let jsonEncoder = JSONEncoder()
                jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
                let jsonData = try jsonEncoder.encode(output)
                let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                #expect(decoded["html"] == "/html/path")
                #expect(decoded["json"] == "/json/path")
            }

            @Test("Text encoding handles special characters in paths")
            func textEncodingSpecialCharacters() throws {
                let specialPath = try AbsolutePath(validating: "/path with/spaces & symbols/coverage.json")
                var output = CoverageFormatOutput()
                try output.addFormat(.json, path: specialPath)

                var encoder = PlainTextEncoder()
                encoder.formattingOptions = [.prettyPrinted]
                let textData = try encoder.encode(output)
                let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(textString == "Json: /path with/spaces & symbols/coverage.json")
            }

            @Test("JSON encoding handles special characters in paths")
            func jsonEncodingSpecialCharacters() throws {
                let specialPath = try AbsolutePath(validating: "/path with/spaces & symbols/coverage.json")
                var output = CoverageFormatOutput()
                try output.addFormat(.json, path: specialPath)

                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let jsonData = try encoder.encode(output)
                let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                #expect(decoded["json"] == "/path with/spaces & symbols/coverage.json")
            }
        }

    }
}
