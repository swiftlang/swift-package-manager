//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation
import Basics
import Testing
@testable import struct _InternalTestSupport.CombinationsWithRepetition

fileprivate let d = [
            [],
            [""],
            ["line1"],
            ["line1", "line2"],
            ["line1", "line2", "line3"],
        ]
fileprivate let prefixAndSuffixData = CombinationsWithRepetition(of: d, length: 2).map( {data in
    // Content(prefix: data.0, suffix: data.1)
    Content(prefix: data[0], suffix: data[1])
})

fileprivate struct Content {
    let prefix: [String]
    let suffix: [String]

    init(prefix pre: [String], suffix: [String]) {
        self.prefix = pre
        self.suffix = suffix
    }

    func getContent(_ value: String) -> String {
        let contentArray: [String] = self.prefix + [value] + self.suffix
        let content = contentArray.joined(separator: "\n")
        return content
    }
}

@Suite
struct ProcessInfoExtensionTests {

    @Suite
    struct isAmazonLinux2 {
        @Test(
            arguments: [
                (contentUT: "", expected: false),
                (contentUT: "ID=", expected: false),
                (contentUT: "ID=foo", expected: false),
                (contentUT: "ID=amzn", expected: true),
                (contentUT: " ID=amzn", expected: false),
            ], prefixAndSuffixData,
        )
        fileprivate func isAmazonLinux2ReturnsExpectedValue(
            data: (contentUT: String, expected: Bool),
            content: Content,
        ) async throws {
            let content = content.getContent(data.contentUT)

            let actual = ProcessInfo.isHostAmazonLinux2(content)

            #expect(actual == data.expected, "Content is: '\(content)'")
        }

        @Test(
            "isHostAmazonLinux2 returns false when not executed on Linux",
            .skipHostOS(.linux),
            .tags(Tag.TestSize.medium),
        )
        func isAmazonLinux2ReturnsFalseWhenNotRunOnLinux() {
            let actual = ProcessInfo.isHostAmazonLinux2()

            #expect(actual == false)
        }
    }
}