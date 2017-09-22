/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageDescription4
import XCTest

class VersionTests: XCTestCase {

    func testBasics() {
        let v1: Version = "1.0.0"
        let v2 = Version(2, 3, 4, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifiers: ["232"])
        XCTAssert(v2 > v1)
        XCTAssertFalse(v2 == v1)
        XCTAssert("1.0.0" == v1)
        XCTAssert(Version(1, 0, 0).hashValue == v1.hashValue)
        XCTAssertLessThan(Version("1.2.3-alpha.beta.2"), Version("1.2.3-alpha.beta.3"))

        XCTAssertEqual(Version("1.2.3-alpha.beta.2")?.description, "1.2.3-alpha.beta.2")
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}

