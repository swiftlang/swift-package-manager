/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
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

    static var allTests = [
        ("testClangVersionOutput", testClangVersionOutput),
    ]
}
