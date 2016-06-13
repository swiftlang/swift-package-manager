/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

// FIXME: Performance tests are disabled for the time being because they have
// too high an impact on overall testing time.
//
// See: https://bugs.swift.org/browse/SR-1354
#if false

class PathPerfTests: XCTestCase {

    func testJoinPerf_X100000() {
        let absPath = AbsolutePath("/hello/little")
        let relPath = RelativePath("world")
        let N = 100000
        self.measure {
            var lengths = 0
            for _ in 0 ..< N {
                let result = absPath.join(relPath)
                lengths = lengths &+ result.asString.utf8.count
            }
            XCTAssertEqual(lengths, (absPath.asString.utf8.count + 1 + relPath.asString.utf8.count) &* N)
        }
    }

    static var allTests = [
        ("testJoinPerf_X100000",         testJoinPerf_X100000),
    ]
}

#endif
