/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TestSupport
import Basic
@testable import Utility

class miscTests: XCTestCase {
    func testClangVersionOutput() {
        var versionOutput = ""
        XCTAssert(getClangVersion(versionOutput: versionOutput) == nil)

        versionOutput = "some - random - string"
        XCTAssert(getClangVersion(versionOutput: versionOutput) == nil)

        versionOutput = "Ubuntu clang version 3.6.0-2ubuntu1~trusty1 (tags/RELEASE_360/final) (based on LLVM 3.6.0)"
        XCTAssert(getClangVersion(versionOutput: versionOutput) ?? (0, 0) == (3, 6))

        versionOutput = "Ubuntu clang version 2.4-1ubuntu3 (tags/RELEASE_34/final) (based on LLVM 3.4)"
        XCTAssert(getClangVersion(versionOutput: versionOutput) ?? (0, 0) == (2, 4))
    }

    func testVersion() throws {
        // Valid.
        XCTAssertEqual(Version(string: "0.9.21-alpha.beta+1011"),
            Version(0,9,21, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifiers: ["1011"]))
        XCTAssertEqual(Version(string: "0.9.21+1011"),
            Version(0,9,21, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1011"]))
        XCTAssertEqual(Version(string: "01.002.0003"), Version(1,2,3))
        XCTAssertEqual(Version(string: "0.9.21"), Version(0,9,21))

        // Invalid.
        let invalidVersions = ["foo", "1", "1.0", "1.0.", "1.0.0."]
        for v in invalidVersions {
            XCTAssertTrue(Version(string: v) == nil)
        }
    }

    static var allTests = [
        ("testClangVersionOutput", testClangVersionOutput),
        ("testVersion", testVersion),
    ]
}
