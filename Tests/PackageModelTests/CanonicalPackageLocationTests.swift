//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

@testable import PackageModel

final class CanonicalPackageLocationTests: XCTestCase {
    func testCaseInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageLocation("MONA/LINKEDLIST").description,
            "mona/linkedlist"
        )

        XCTAssertEqual(
            CanonicalPackageLocation("mona/linkedlist").description,
            "mona/linkedlist"
        )
    }

    func testNormalizationInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageLocation("mona/e\u{0301}clair").description, // ◌́ COMBINING ACUTE ACCENT (U+0301)
            "mona/éclair"
        )

        XCTAssertEqual(
            CanonicalPackageLocation("mona/\u{00C9}clair").description, // LATIN CAPITAL LETTER E WITH ACUTE (U+00C9)
            "mona/éclair"
        )
    }

    func testCaseAndNormalizationInsensitivity() {
        XCTAssertEqual(
            CanonicalPackageLocation("mona/E\u{0301}clair").description, // ◌́ COMBINING ACUTE ACCENT (U+0301)
            "mona/éclair"
        )
    }

    // MARK: - Filesystem

    func testFileScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("file:///Users/mona/LinkedList").description,
            "/users/mona/linkedlist"
        )
    }

    func testImplicitFileSchemeWithAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageLocation("/Users/mona/LinkedList").description,
            "/users/mona/linkedlist"
        )
    }

    // MARK: - FTP / FTPS

    func testFTPScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("ftp://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testFTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("ftps://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    // MARK: - HTTP / HTTPS

    func testHTTPScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("http://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithUser() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://user@example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithUserAndPassword() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://user:sw0rdf1sh!@example.com/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com:443/mona/LinkedList").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList/").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.git/").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithGitSuffixAndSwiftExtension() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.swift.git").description,
            "example.com/mona/linkedlist.swift"
        )
    }

    func testHTTPSSchemeWithQuery() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithQueryAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList/?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithQueryAndGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.git?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragment() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndTrailingSlash() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList/#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndGitSuffix() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.git#installation").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithFragmentAndQuery() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/LinkedList.git#installation?utm_source=forums.swift.org").description,
            "example.com/mona/linkedlist"
        )
    }

    func testHTTPSSchemeWithPercentEncoding() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/%F0%9F%94%97List").description,
            "example.com/mona/🔗list"
        )
    }

    func testHTTPSSchemeWithInvalidPercentEncoding() {
        XCTAssertEqual(
            CanonicalPackageLocation("https://example.com/mona/100%").description,
            "example.com/mona/100%"
        )
    }

    func testHTTPSSchemeWithInternationalizedDomainName() throws {
        // TODO: Implement Punycode conversion
        try XCTSkipIf(true, "internationalized domain names aren't yet supported")

        XCTAssertEqual(
            CanonicalPackageLocation("https://xn--schlssel-95a.tld/mona/LinkedList").description,
            "schlüssel.tld/mona/LinkedList"
        )
    }

    // MARK: - Git

    func testGitScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("git://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testGitSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageLocation("git://example.com:9418/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testGitPlusHTTPSScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("git+https://example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    // MARK: - SSH

    func testSSHScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://git@example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://git@example.com:mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://git@example.com:/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithPort() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://git@example.com:22/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://mona@example.com/~/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageLocation("ssh://git@example.com/~mona/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHScheme() {
        XCTAssertEqual(
            CanonicalPackageLocation("git@example.com/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonAndRelativePath() {
        XCTAssertEqual(
            CanonicalPackageLocation("git@example.com:mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonAndAbsolutePath() {
        XCTAssertEqual(
            CanonicalPackageLocation("git@example.com:/mona/LinkedList.git").description,
            "example.com/mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageLocation("mona@example.com/~/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithoutTildeExpansion() {
        XCTAssertEqual(
            CanonicalPackageLocation("git@example.com/~mona/LinkedList.git").description,
            "example.com/~mona/linkedlist"
        )
    }

    func testImplicitSSHSchemeWithColonInPathComponent() {
        XCTAssertEqual(
            CanonicalPackageLocation("user:sw0rdf1sh!@example.com:/mona/Linked:List.git").description,
            "example.com/mona/linked:list"
        )
    }

    func testScheme() {
        XCTAssertEqual(CanonicalPackageURL("https://example.com/mona/LinkedList").scheme, "https")
        XCTAssertEqual(CanonicalPackageURL("git@example.com/mona/LinkedList").scheme, "ssh")
        XCTAssertEqual(CanonicalPackageURL("git@example.com:mona/LinkedList.git ").scheme, "ssh")
        XCTAssertEqual(CanonicalPackageURL("ssh://mona@example.com/~/LinkedList.git").scheme, "ssh")
        XCTAssertEqual(CanonicalPackageURL("file:///Users/mona/LinkedList").scheme, "file")
        XCTAssertEqual(CanonicalPackageURL("example.com:443/mona/LinkedList").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("example.com/mona/%F0%9F%94%97List").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("example.com/mona/LinkedList.git").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("example.com/mona/LinkedList/").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("example.com/mona/LinkedList#installation").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("example.com/mona/LinkedList?utm_source=forums.swift.org").scheme, nil)
        XCTAssertEqual(CanonicalPackageURL("user:sw0rdf1sh!@example.com:/mona/Linked:List.git").scheme, nil)
    }
}
