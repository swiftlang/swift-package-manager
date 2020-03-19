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

class SynchronizedQueuePerfTests: XCTestCasePerf {
    
    // Mock the UnitTest struct in SwiftPM/SwiftTestTool.swift
    struct Item {
        let productPath: AbsolutePath
        
        let name: String
        
        let testCase: String
        
        var specifier: String {
            return testCase + "/" + name
        }
    }

    
    func testEnqueueDequeue_10000() {
        let queue = SynchronizedQueue<Item>()
        let test = Item(productPath: AbsolutePath.root, name: "TestName", testCase: "TestCaseName")
        measure {
            let N = 10000
            for _ in 0..<N {
                queue.enqueue(test)
            }
            for _ in 0..<N {
                let _ = queue.dequeue()
            }
        }
    }
    
    func testEnqueueDequeue_1000() {
        let queue = SynchronizedQueue<Item>()
        let test = Item(productPath: AbsolutePath.root, name: "TestName", testCase: "TestCaseName")
        measure {
            let N = 1000
            for _ in 0..<N {
                queue.enqueue(test)
            }
            for _ in 0..<N {
                let _ = queue.dequeue()
            }
        }
    }
    
    func testEnqueueDequeue_100() {
        let queue = SynchronizedQueue<Item>()
        let test = Item(productPath: AbsolutePath.root, name: "TestName", testCase: "TestCaseName")
        measure {
            let N = 100
            for _ in 0..<N {
                queue.enqueue(test)
            }
            for _ in 0..<N {
                let _ = queue.dequeue()
            }
        }
    }
    
}
