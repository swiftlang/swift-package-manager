/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageType
import XCTest

class PackageTests: XCTestCase {

    func testUrlEndsInDotGit1() {
        let uid = Package.nameForURL("https://github.com/foo/bar.git")
        XCTAssertEqual(uid, "bar")
    }

    func testUrlEndsInDotGit2() {
        let uid = Package.nameForURL("http://github.com/foo/bar.git")
        XCTAssertEqual(uid, "bar")
    }

    func testUrlEndsInDotGit3() {
        let uid = Package.nameForURL("git@github.com/foo/bar.git")
        XCTAssertEqual(uid, "bar")
    }

    func testUid() {
        let uid = Package.nameForURL("http://github.com/foo/bar")
        XCTAssertEqual(uid, "bar")
    }
}


extension PackageTests {
    static var allTests : [(String, (PackageTests) -> () throws -> Void)] {
        return [
            ("testUrlEndsInDotGit1", testUrlEndsInDotGit1),
            ("testUrlEndsInDotGit2", testUrlEndsInDotGit2),
            ("testUrlEndsInDotGit3", testUrlEndsInDotGit3),
            ("testUid", testUid),
        ]
    }
}
