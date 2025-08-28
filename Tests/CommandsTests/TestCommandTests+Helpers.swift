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
import func Commands.getOutputDir


@Suite(
    .tags(
        .TestSize.small,
    )
)
struct TestCommmandHelperTests {

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
            let actual = try getOutputDir(from: content)

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
            let actual = try getOutputDir(from: data.content)

            #expect(actual == data.expected)
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
}