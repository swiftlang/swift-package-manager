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

    func testGitScheme() {
        XCTAssertEqual(
            PackageIdentity("git://example.com/mona/LinkedList.git"),
            "example.com/mona/LinkedList"
        )
    }
}
