/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import POSIX
import class Foundation.NSDate

class UsleepTests: XCTestCase {

    func testBasics() throws {
        let ms = 10000
        let startTime = NSDate().timeIntervalSince1970
        try usleep(microSeconds: ms)
        let endTime = NSDate().timeIntervalSince1970
        let diff = Int((endTime - startTime) * 1000000)

        XCTAssert(diff >= ms, "Slept for \(diff) usec, which is less than \(ms) usec")
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
