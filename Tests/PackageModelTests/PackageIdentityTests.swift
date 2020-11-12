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

    func testTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/"),
            "example.com/mona/LinkedList"
        )
    }

    func testGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }

    func testGitSuffixWithTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git/"),
            "example.com/mona/LinkedList"
        )
    }

    func testGitSuffixAndSwiftExtension() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.swift.git"),
            "example.com/mona/LinkedList.swift"
        )
    }

    func testQuery() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testQueryWithTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testQueryWithGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testFragment() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testFragmentWithTrailingSlash() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList/#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testFragmentWithGitSuffix() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git#installation"),
            "example.com/mona/LinkedList"
        )
    }

    func testFragmentAndQuery() {
        XCTAssertEqual(
            PackageIdentity("https://example.com/mona/LinkedList.git#installation?utm_source=forums.swift.org"),
            "example.com/mona/LinkedList"
        )
    }

    func testHTTPScheme() {
        XCTAssertEqual(
            PackageIdentity("http://example.com/mona/LinkedList"),
            "example.com/mona/LinkedList"
        )
    }

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
}
