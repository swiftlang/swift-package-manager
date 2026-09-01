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

import Foundation
import Testing

import struct Basics.AbsolutePath
import enum Commands.CoverageFormat
import struct Commands.CoverageFormatOutput
import struct Commands.PlainTextEncoder

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct TestCommmandHelpersTests {

    @Suite
    struct CoverageFormatOutputTests {

        @Suite(
            .tags(
                .TestSize.small,
                .Feature.Encoding,
            ),
        )
        struct EncodingTests {
            @Suite
            struct JsonEncodingTests {
                @Test("Encode as JSON with single format")
                func encodeAsJSONSingle() throws {
                    let path = try AbsolutePath(validating: "/path/to/coverage.json")
                    let output = CoverageFormatOutput(data: [.json: path])

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    let jsonData = try encoder.encode(output)
                    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                    #expect(decoded["json"] == "/path/to/coverage.json")
                    #expect(decoded.count == 1)
                }

                @Test("Encode as JSON with multiple formats")
                func encodeAsJSONMultiple() throws {
                    let jsonPath = try AbsolutePath(validating: "/path/to/coverage.json")
                    let htmlPath = try AbsolutePath(validating: "/path/to/coverage-html")

                    let output = CoverageFormatOutput(
                        data: [
                            .json: jsonPath,
                            .html: htmlPath,
                        ],
                    )

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    encoder.outputFormatting = [.prettyPrinted]
                    let jsonData = try encoder.encode(output)
                    let jsonString = String(decoding: jsonData, as: UTF8.self)
                    let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                    #expect(decoded["json"] == "/path/to/coverage.json")
                    #expect(decoded["html"] == "/path/to/coverage-html")
                    #expect(decoded.count == 2)

                    #expect(jsonString.contains("{\n"))
                    #expect(jsonString.contains("\n}"))
                }

                @Test("Encode as JSON with empty data")
                func encodeAsJSONEmpty() throws {
                    let output = CoverageFormatOutput(data: [:])

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
                    let output = CoverageFormatOutput(data: [format: path])

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

                    let output = CoverageFormatOutput(
                        data: [
                            .json: jsonPath,
                            .html: htmlPath,
                        ],
                    )

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
                    let output = CoverageFormatOutput(data: [:])

                    var encoder = PlainTextEncoder()
                    encoder.formattingOptions = [.prettyPrinted]
                    let textData = try encoder.encode(output)
                    let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                    #expect(textString.isEmpty)
                }
            }

            @Test("Encoding consistency - formats maintain sorting")
            func encodingConsistency() throws {
                let jsonPath = try AbsolutePath(validating: "/json/path")
                let htmlPath: AbsolutePath = try AbsolutePath(validating: "/html/path")

                let output = CoverageFormatOutput(
                    data: [
                        .json: jsonPath,
                        .html: htmlPath,
                    ],
                )

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
                let output = CoverageFormatOutput(data: [.json: specialPath])

                var encoder = PlainTextEncoder()
                encoder.formattingOptions = [.prettyPrinted]
                let textData = try encoder.encode(output)
                let textString = String(decoding: textData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(textString == "Json: /path with/spaces & symbols/coverage.json")
            }

            @Test("JSON encoding handles special characters in paths")
            func jsonEncodingSpecialCharacters() throws {
                let specialPath = try AbsolutePath(validating: "/path with/spaces & symbols/coverage.json")
                let output = CoverageFormatOutput(data: [.json: specialPath])

                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let jsonData = try encoder.encode(output)
                let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: String]

                #expect(decoded["json"] == "/path with/spaces & symbols/coverage.json")
            }
        }

    }
}
