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

final class LegacyPackageIdentityTests: XCTestCase {
    func testPackageIdentityDescriptions() {
        XCTAssertEqual(PackageIdentity("foo").description, "foo")
        XCTAssertEqual(PackageIdentity("/foo").description, "foo")
        XCTAssertEqual(PackageIdentity("/foo/bar").description, "bar")
        XCTAssertEqual(PackageIdentity("foo/bar").description, "bar")
        XCTAssertEqual(PackageIdentity("https://foo/bar/baz").description, "baz")
        XCTAssertEqual(PackageIdentity("git@github.com/foo/bar/baz").description, "baz")
        XCTAssertEqual(PackageIdentity("/path/to/foo/bar/baz/").description, "baz")
        XCTAssertEqual(PackageIdentity("https://foo/bar/baz.git").description, "baz")
        XCTAssertEqual(PackageIdentity("git@github.com/foo/bar/baz.git").description, "baz")
        XCTAssertEqual(PackageIdentity("/path/to/foo/bar/baz.git").description, "baz")
    }
}
