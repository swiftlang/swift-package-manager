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

final class PackageIdentityParserTests: XCTestCase {
    func testPackageIdentityDescriptions() {
        XCTAssertEqual(PackageIdentityParser("foo").description, "foo")
        XCTAssertEqual(PackageIdentityParser("/foo").description, "foo")
        XCTAssertEqual(PackageIdentityParser("/foo/bar").description, "bar")
        XCTAssertEqual(PackageIdentityParser("foo/bar").description, "bar")
        XCTAssertEqual(PackageIdentityParser("https://foo/bar/baz").description, "baz")
        XCTAssertEqual(PackageIdentityParser("git@github.com/foo/bar/baz").description, "baz")
        XCTAssertEqual(PackageIdentityParser("/path/to/foo/bar/baz/").description, "baz")
        XCTAssertEqual(PackageIdentityParser("https://foo/bar/baz.git").description, "baz")
        XCTAssertEqual(PackageIdentityParser("git@github.com/foo/bar/baz.git").description, "baz")
        XCTAssertEqual(PackageIdentityParser("/path/to/foo/bar/baz.git").description, "baz")
    }
}
