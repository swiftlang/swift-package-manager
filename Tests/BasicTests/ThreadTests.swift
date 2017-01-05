/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

typealias Thread = Basic.Thread

class ThreadTests: XCTestCase {

    func testSingleThread() {
        var finished = false

        let thread = Thread {
            finished = true
        }

        thread.start()
        thread.join()

        XCTAssertTrue(finished)
    }

    func testMultipleThread() {
        var finishedOne = false
        var finishedTwo = false

        let threadOne = Thread {
            finishedOne = true
        }

        let threadTwo = Thread {
            finishedTwo = true
        }

        threadOne.start()
        threadTwo.start()
        threadOne.join()
        threadTwo.join()

        XCTAssertTrue(finishedOne)
        XCTAssertTrue(finishedTwo)
    }

    func testNotDeinitBeforeExecutingTask() {
        let finishedCondition = Condition()
        var finished = false

        Thread {
            finishedCondition.whileLocked{
                finished = true
                finishedCondition.signal()
            }
        }.start()

        finishedCondition.whileLocked{
            while !finished {
                finishedCondition.wait()
            }
        }

        XCTAssertTrue(finished)
    }

    static var allTests = [
        ("testSingleThread", testSingleThread),
        ("testMultipleThread", testMultipleThread),
        ("testNotDeinitBeforeExecutingTask", testNotDeinitBeforeExecutingTask),
    ]
}
