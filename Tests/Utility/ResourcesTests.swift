/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utility

public var globalSymbolInNonMainBinary = 0

class ResourcesTests: XCTestCase {

    func testResources() {
        // Cause resources to be initialized, even though the path won't actually be correct.
        Resources.initialize(&globalSymbolInNonMainBinary)

        let basename: String
    #if os(Linux)
        basename = "test-Package"
    #else
        basename = "Package"
    #endif

        // Check that we located the path of the test bundle executable
        XCTAssertEqual(Resources.getMainExecutable()?.basename, basename)
    }
}
