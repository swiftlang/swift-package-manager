/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class ConditionTests: XCTestCase {
    func testSignal() {
        let condition = Condition()
        var waiting = false
        var doneWaiting = false
        let thread = Thread {
            condition.whileLocked{
                waiting = true
                condition.wait()
                doneWaiting = true
            }
        }
        thread.start()
        
        // Wait for the thread to start waiting
        while condition.whileLocked({ !waiting }) {}

        // Signal and wait for the thread to complete.
        condition.whileLocked{
            condition.signal()
        }
        thread.join()

        // Wait for the thread to complete.
        XCTAssert(doneWaiting)
    }

    func testBroadcast() {
        let condition = Condition()
        var waiting = [false, false]
        var doneWaiting = [false, false]
        let threads = [0, 1].map { i -> Thread in
            let thread = Thread {
                condition.whileLocked{
                    waiting[i] = true
                    condition.wait()
                    doneWaiting[i] = true
                }
            }
            thread.start()
            return thread
        }
        
        // Wait for each thread to start waiting.
        while condition.whileLocked({ !waiting[0] || !waiting[1] }) {}

        // Signal and wait for the thread to complete.
        condition.whileLocked{
            condition.broadcast()
        }
        threads.forEach{ $0.join() }

        // Wait for each thread to complete.
        XCTAssert(doneWaiting[0])
        XCTAssert(doneWaiting[1])
    }

    static var allTests = [
        ("testSignal", testSignal),
        ("testBroadcast", testBroadcast),
    ]
}
