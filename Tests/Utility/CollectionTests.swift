/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Utility
import XCTest

class CollectionTests: XCTestCase {
    
    func testPick() {
        
        let body = { (num: Int) -> Bool in num > 5 }
        
        XCTAssertNil([].pick(body))
        XCTAssertNil([3, 4].pick(body))
        XCTAssertEqual([3, 7].pick(body), 7)
        XCTAssertEqual([3, 8, 7].pick(body), 8)
    }
    
    func testPartitionByType() {
        
        let input0: [Any] = []
        let output0: ([String], [Int]) = input0.partition()
        XCTAssertEqual(output0.0, [String]())
        XCTAssertEqual(output0.1, [Int]())
        
        let input1: [Any] = [1, "two", 3, "four"]
        let output1: ([String], [Int]) = input1.partition()
        XCTAssertEqual(output1.0, ["two", "four"])
        XCTAssertEqual(output1.1, [1, 3])
    }
    
    func testPartitionByClosure() {
        
        func eq(_ lhs: ([Int], [Int]), _ rhs: ([Int], [Int]), file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(lhs.0, rhs.0, file: file, line: line)
            XCTAssertEqual(lhs.1, rhs.1, file: file, line: line)
        }
        
        let body = { (num: Int) -> Bool in num > 5 }
        
        eq([Int]().partition(body), ([], []))
        eq([2].partition(body), ([], [2]))
        eq([7].partition(body), ([7], []))
        eq([7, 4, 2, 9].partition(body), ([7, 9], [4, 2]))
    }
    
    func testSplitAround() {
        
        func eq(_ lhs: ([Character], [Character]?), _ rhs: ([Character], [Character]?), file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(lhs.0, rhs.0, file: file, line: line)
            XCTAssertEqual(lhs.1 ?? [], rhs.1 ?? [], file: file, line: line)
        }
        
        eq([].split(around: [":"]), ([], nil))
        eq(["f", "o", "o"].split(around: [":"]), (["f", "o", "o"], nil))
        eq(["f", "o", "o", ":"].split(around: [":"]), (["f", "o", "o"], []))
        eq([":", "b", "a", "r"].split(around: [":"]), ([], ["b", "a", "r"]))
        eq(["f", "o", "o", ":", "b", "a", "r"].split(around: [":"]), (["f", "o", "o"], ["b", "a", "r"]))
    }

    func testUnique() {
       XCTAssertEqual(["a", "b", "c"].unique(), ["a", "b", "c"])
       XCTAssertEqual(["f", "o", "o"].unique(), ["f", "o"])
       XCTAssertEqual(["f", "o", "b", "o", "a", "r"].unique(), ["f", "o", "b", "a", "r"])
       XCTAssertEqual(["f", "f", "o", "b", "f", "b"].unique(), ["f", "o", "b"])
    }

    static var allTests = [
        ("testPick", testPick),
        ("testPartitionByType", testPartitionByType),
        ("testPartitionByClosure", testPartitionByClosure),
        ("testSplitAround", testSplitAround),
        ("testUnique", testUnique)
    ]
}

