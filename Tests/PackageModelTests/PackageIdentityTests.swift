/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import TSCBasic

import PackageModel

final class PackageIdentityTests: XCTestCase {
    func testCaseInsensitivity() {
        XCTAssertEqual(
            PackageIdentity("MONA/LINKEDLIST"),
            PackageIdentity("mona/LinkedList")
        )
    }

    func testNormalizationInsensitivity() {
        XCTAssertEqual(
            PackageIdentity("mona/E\u{0301}clair"), // ◌́ COMBINING ACUTE ACCENT (U+0301)
            PackageIdentity("mona/\u{00C9}clair") // LATIN CAPITAL LETTER E WITH ACUTE (U+00C9)
        )
    }

    func testCaseAndNormalizationInsensitivity() {
        XCTAssertEqual(
            PackageIdentity("mona/e\u{0301}clair"), // ◌́ COMBINING ACUTE ACCENT (U+0301)
            PackageIdentity("MONA/\u{00C9}CLAIR") // LATIN CAPITAL LETTER E WITH ACUTE (U+00C9)
        )
    }

    // MARK: - Filesystem

    func testFileScheme() {
        XCTAssertEqual(
            PackageIdentity("file:///Users/mona/LinkedList"),
            "Users/mona/LinkedList"
        )
    }

    func testImplicitFileSchemeWithAbsolutePath() {
        XCTAssertEqual(
            PackageIdentity("/Users/mona/LinkedList"),
            "Users/mona/LinkedList"
        )
    }

    // MARK: - FTP / FTPS

    func testFTPScheme() {
        XCTAssertEqual(
            PackageIdentity("ftp://example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testFTPSScheme() {
        XCTAssertEqual(
            PackageIdentity("ftps://example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    // MARK: - HTTP / HTTPS

    func testHTTPScheme() {
        XCTAssertEqual(
            PackageIdentity("http://example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSScheme() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithUser() {
        XCTAssertEqual(
            PackageIdentity("https://user@example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithUserAndPassword() {
        XCTAssertEqual(
            PackageIdentity("https://user:sw0rdf1sh!@example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithPort() {
        XCTAssertEqual(
            PackageIdentity("https://example.com:443/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git/"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndSwiftExtension() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.swift.git"),
            "example.com/mona/LinkedList.swift"
        )
    }

    func testHTTPSSchemeWithQuery() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithQueryAndTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithQueryAndGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithFragment() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithFragmentAndTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithFragmentAndGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithFragmentAndQuery() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git#installation?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPSSchemeWithPercentEncoding() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/%F0%9F%94%97List"),
            "example.com/mona/🔗List"
        )
    }

    func testHTTPSSchemeWithInvalidPercentEncoding() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/100%"),
            "example.com/mona/100%"
        )
    }

    func testHTTPSSchemeWithInternationalizedDomainName() throws {
        // TODO: Implement Punycode conversion
        try XCTSkipIf(true, "internationalized domain names aren't yet supported")

        XCTAssertEqual(
            PackageIdentity("https://xn--schlssel-95a.tld/mona/LinkedList"),
            "schlüssel.tld/mona/LinkedList"
        )
    }

    // MARK: - Git

    func testGitScheme() {
        XCTAssertEqual(
            PackageIdentity("git://example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testGitSchemeWithPort() {
        XCTAssertEqual(
            PackageIdentity("git://example.com:9418/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testGitPlusHTTPSScheme() {
        XCTAssertEqual(
            PackageIdentity("git+https://example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    // MARK: - SSH

    func testSSHScheme() {
        XCTAssertEqual(
            PackageIdentity("ssh://git@example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            PackageIdentity("ssh://git@example.com:mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            PackageIdentity("ssh://git@example.com:/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testSSHSchemeWithPort() {
        XCTAssertEqual(
            PackageIdentity("ssh://git@example.com:22/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            PackageIdentity("ssh://mona@example.com/~/LinkedList.git"),
            "example.com/~mona/LinkedList"
        )
    }

    func testSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            PackageIdentity("ssh://git@example.com/~mona/LinkedList.git"),
            "example.com/~mona/LinkedList"
        )
    }

    func testImplicitSSHScheme() {
        XCTAssertEqual(
            PackageIdentity("git@example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testImplicitSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            PackageIdentity("git@example.com:mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testImplicitSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            PackageIdentity("git@example.com:/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testImplicitSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            PackageIdentity("mona@example.com/~/LinkedList.git"),
            "example.com/~mona/LinkedList"
        )
    }

    func testImplicitSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            PackageIdentity("git@example.com/~mona/LinkedList.git"),
            "example.com/~mona/LinkedList"
        )
    }

    func testImplicitSSHSchemeWithColonInPathComponent() {
        XCTAssertEqual(
            PackageIdentity("user:sw0rdf1sh!@example.com:/mona/Linked:List.git"),
            "example.com/mona/Linked:List"
        )
    }
}
