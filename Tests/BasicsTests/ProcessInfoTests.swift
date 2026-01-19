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
    struct isHost {
        @Test(
            arguments: [
                (
                    contentUT: "",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=foo",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=amzn",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=Amazon Linux 2",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=Amazon Linux 2023.6.20250107",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: " PRETTY_NAME=amzn",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: "PRETTY_NAME=\"Amazon Linux 2\"",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: true,
                ),
                (
                    contentUT: "PRETTY_NAME=\"Amazon Linux 2 (something else)\"",
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                ),
                (
                    contentUT: """
                        NAME="Amazon Linux"
                        VERSION="2"
                        ID="amzn"
                        ID_LIKE="centos rhel fedora"
                        VERSION_ID="2"
                        PRETTY_NAME="Amazon Linux 2"
                        ANSI_COLOR="0;33"
                        CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2"
                        HOME_URL="https://amazonlinux.com/"
                        SUPPORT_END="2026-06-30"
                        """,
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: true
                ),
                (
                    contentUT: """
                        NAME="Amazon Linux"
                        VERSION="2"
                        ID="amzn"
                        ID_LIKE="centos rhel fedora"
                        VERSION_ID="2"
                        PRETTY_NAME="Amazon Linux 2 (something else)"
                        ANSI_COLOR="0;33"
                        CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2"
                        HOME_URL="https://amazonlinux.com/"
                        SUPPORT_END="2026-06-30"
                        """,
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false
                ),
                (
                    contentUT: """
                        NAME="Amazon Linux"
                        VERSION="2"
                        ID="amzn"
                        ID_LIKE="centos rhel fedora"
                        VERSION_ID="2"
                        PRETTY_NAME=Amazon Linux 2 (something else)
                        ANSI_COLOR="0;33"
                        CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2"
                        HOME_URL="https://amazonlinux.com/"
                        SUPPORT_END="2026-06-30"
                        """,
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false
                ),
                (
                    contentUT: """
                        NAME="Amazon Linux"
                        VERSION="2"
                        ID="amzn"
                        ID_LIKE="centos rhel fedora"
                        VERSION_ID="2"
                        PRETTY_NAME=Amazon Linux 2
                        ANSI_COLOR="0;33"
                        CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2"
                        HOME_URL="https://amazonlinux.com/"
                        SUPPORT_END="2026-06-30"
                        """,
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false
                ),
                (
                    contentUT: """
                    NAME="Amazon Linux"
                    VERSION="2023"
                    ID="amzn"
                    ID_LIKE="fedora"
                    VERSION_ID="2023"
                    PLATFORM_ID="platform:al2023"
                    PRETTY_NAME="Amazon Linux 2023.6.20250107"
                    ANSI_COLOR="0;33"
                    CPE_NAME="cpe:2.3:o:amazon:amazon_linux:2023"
                    HOME_URL="https://aws.amazon.com/linux/amazon-linux-2023/"
                    DOCUMENTATION_URL="https://docs.aws.amazon.com/linux/"
                    SUPPORT_URL="https://aws.amazon.com/premiumsupport/"
                    BUG_REPORT_URL="https://github.com/amazonlinux/amazon-linux-2023"
                    VENDOR_NAME="AWS"
                    VENDOR_URL="https://aws.amazon.com/"
                    SUPPORT_END="2028-03-15"
                    """,
                    hostToMatch: "PRETTY_NAME=\"Amazon Linux 2\"",
                    expected: false,
                )
            ], prefixAndSuffixData,
        )
        fileprivate func isAmazonLinux2ReturnsExpectedValue(
            data: (contentUT: String, hostToMatch: String, expected: Bool),
            content: Content,
        ) async throws {
            let content = content.getContent(data.contentUT)

            let actual = ProcessInfo.isHost(osName: data.hostToMatch, content)

            #expect(actual == data.expected, "Content is: '\(content)'")
        }

        @Test(
            "isHost* returns false when not executed on Linux",
            .skipHostOS(.linux),
            .tags(Tag.TestSize.medium),
        )
        func concreteIsHostReturnsFalseWhenNotRunOnLinux() {
            let actualAL2 = ProcessInfo.isHostAmazonLinux2()
            #expect(actualAL2 == false)

            let actualRHEL9 = ProcessInfo.isHostRHEL9()
            #expect(actualRHEL9 == false)
        }
    }
}
