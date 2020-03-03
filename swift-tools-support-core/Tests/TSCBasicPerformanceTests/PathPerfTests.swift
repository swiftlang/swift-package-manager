/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCTestSupport

class PathPerfTests: XCTestCasePerf {
    
    /// Tests creating very long AbsolutePaths by joining path components.
    func testJoinPerf_X100000() {
      #if os(macOS)
        let absPath = AbsolutePath("/hello/little")
        let relPath = RelativePath("world")
        let N = 100000
        self.measure {
            var lengths = 0
            for _ in 0 ..< N {
                let result = absPath.appending(relPath)
                lengths = lengths &+ result.pathString.utf8.count
            }
            XCTAssertEqual(lengths, (absPath.pathString.utf8.count + 1 + relPath.pathString.utf8.count) &* N)
        }
      #endif
    }
}
