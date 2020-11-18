/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import TSCBasic

@testable import PackageModel

final class CanonicalPackageIdentityTests: XCTestCase {
    func testCaseInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageIdentity("MONA/LINKEDLIST").description,
            "mona/linkedlist"
        )

        XCTAssertEqual(
            CanonicalPackageIdentity("mona/linkedlist").description,
            "mona/linkedlist"
        )
    }

    func testNormalizationInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageIdentity("mona/e\u{0301}clair").description, // ◌́ COMBINING ACUTE ACCENT (U+0301)
            "mona/éclair"
        )

        XCTAssertEqual(
            CanonicalPackageIdentity("mona/\u{00C9}clair").description, // LATIN CAPITAL LETTER E WITH ACUTE (U+00C9)
            "mona/éclair"
        )
    }

    func testCaseAndNormalizationInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageIdentity("mona/E\u{0301}clair").description, // ◌́ COMBINING ACUTE ACCENT (U+0301)
            "mona/éclair"
        )
    }

    // MARK: - Filesystem

    func testFileScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("file:///Users/mona/LinkedList").description,
            "/users/mona/linkedlist"
        )
    }

    func testImplicitFileSchemeWithAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageIdentity("/Users/mona/LinkedList").description,
            "/users/mona/linkedlist"
        )
    }

    // MARK: - FTP / FTPS

    func testFTPScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ftp://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testFTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ftps://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    // MARK: - HTTP / HTTPS

    func testHTTPScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("http://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithUser() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://user@example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithUserAndPassword() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://user:sw0rdf1sh!@example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com:443/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList/").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.git/").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndSwiftExtension() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.swift.git").description,
            "example.com/mona/linkedlist.swift"
        )
    }

    func testHTTPSSchemeWithQuery() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithQueryAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList/?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithQueryAndGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.git?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragment() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList/#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.git#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndQuery() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/LinkedList.git#installation?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithPercentEncoding() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/%F0%9F%94%97List").description,
            "example.com/mona/🔗list"
        )
    }

    func testHTTPSSchemeWithInvalidPercentEncoding() {
        XCTAssertEqual(
            CanonicalPackageIdentity("https://example.com/mona/100%").description,
            "example.com/mona/100%"
        )
    }

    func testHTTPSSchemeWithInternationalizedDomainName() throws {
        // TODO: Implement Punycode conversion
        try XCTSkipIf(true, "internationalized domain names aren't yet supported")

        XCTAssertEqual(
            CanonicalPackageIdentity("https://xn--schlssel-95a.tld/mona/LinkedList").description,
            "schlüssel.tld/mona/LinkedList"
        )
    }

    // MARK: - Git

    func testGitScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testGitSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git://example.com:9418/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testGitPlusHTTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git+https://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    // MARK: - SSH

    func testSSHScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://git@example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://git@example.com:mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://git@example.com:/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://git@example.com:22/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://mona@example.com/~/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageIdentity("ssh://git@example.com/~mona/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHScheme() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git@example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git@example.com:mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git@example.com:/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageIdentity("mona@example.com/~/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageIdentity("git@example.com/~mona/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonInPathComponent() {
        XCTAssertEqual(
            CanonicalPackageIdentity("user:sw0rdf1sh!@example.com:/mona/Linked:List.git").description,
            "example.com/mona/linked:list"
        )
    }
}
