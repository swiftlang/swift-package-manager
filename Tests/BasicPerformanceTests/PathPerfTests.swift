/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import TestSupport

class PathPerfTests: XCTestCasePerf {
    
    /// Tests creating very long AbsolutePaths by joining path components.
    func testJoinPerf_X100000() {
        let absPath = AbsolutePath("/hello/little")
        let relPath = RelativePath("world")
        let N = 100000
        self.measure {
            var lengths = 0
            for _ in 0 ..< N {
                let result = absPath.appending(relPath)
                lengths = lengths &+ result.asString.utf8.count
            }
            XCTAssertEqual(lengths, (absPath.asString.utf8.count + 1 + relPath.asString.utf8.count) &* N)
        }
    }
    
    // FIXME: We will obviously want a lot more tests here.
}
