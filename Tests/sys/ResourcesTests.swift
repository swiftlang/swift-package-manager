/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import sys

public var globalSymbolInNonMainBinary = 0

class ResourcesTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testResources", testResources),
        ]
    }

    func testResources() {
        // Cause resources to be initialized, even though the path won't actually be correct.
        Resources.initialize(&globalSymbolInNonMainBinary)

        // Check that we located the path of the test bundle.
        XCTAssertEqual(Resources.getMainExecutable().flatMap({ $0.basename }), "sys-tests")
    }
}
