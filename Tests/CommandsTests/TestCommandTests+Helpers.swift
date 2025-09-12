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
        @Test func outputDirArgumentNotPresentReturnsNil() async throws {
            let actual = try getOutputDir(from: "")

            #expect(actual == nil)
        }

        @Test
        func contentContainsOutputDirectoryReturnsCorrectPath() async throws {
            let expected = AbsolutePath("/Bar/baz")
            let content = """
            --output-dir=\(expected)
            """

            let actual = try getOutputDir(from: content)

            #expect(actual == expected)
        }

        @Test func sample() async throws {
            let logMessage = "ERROR: User 'john.doe' failed login attempt from IP 192.168.1.100."

            // Create a Regex with named capture groups for user and ipAddress
            let regex = try! Regex("User '(?<user>[a-zA-Z0-9.]+)' failed login attempt from IP (?<ipAddress>\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})")

            // Find the first match in the log message
            if let match = logMessage.firstMatch(of: regex) {
                // Access the captured values using their named properties
                let username = match.user
                let ipAddress = match.ipAddress

                expect(Bool(true))
            } else {
                expect(Bool(false))
            }

        }
    }
}