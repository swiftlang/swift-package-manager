/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import POSIX

class ReaddirTests: XCTestCase {
    func testName() {
        do {
            var s = dirent()
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = unsafeBitCast(ptr, to: UnsafeMutablePointer<UInt8>.self)
                ptr[0] = UInt8(ascii: "A")
                ptr[1] = UInt8(ascii: "B")
            }
            s.d_namlen = 2
            XCTAssertEqual(s.name, "AB")
        }
        
        do {
            var s = dirent()
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = unsafeBitCast(ptr, to: UnsafeMutablePointer<UInt8>.self)
                ptr[0] = 0xFF
                ptr[1] = 0xFF
            }
            s.d_namlen = 2
            XCTAssertEqual(s.name, nil)
        }
        
        do {
            var s = dirent()
            let n = sizeof(s.d_name.dynamicType)
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = unsafeBitCast(ptr, to: UnsafeMutablePointer<UInt8>.self)
                for i in 0 ..< n {
                    ptr[i] = UInt8(ascii: "A")
                }
            }
            s.d_namlen = UInt16(n)
            XCTAssertEqual(s.name, String(repeating: "A", count: n))
        }
    }
    
    static var allTests: [(String, (ReaddirTests) -> () throws -> Void)] = [
        ("testName", testName),
    ]
}
