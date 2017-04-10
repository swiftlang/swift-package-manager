/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import POSIX

extension MemoryLayout {
  fileprivate static func ofInstance(_: @autoclosure () -> T) -> MemoryLayout<T>.Type {
    return MemoryLayout<T>.self
  }
}

class ReaddirTests: XCTestCase {
    func testName() {
        do {
            var s = dirent()
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
                ptr[0] = UInt8(ascii: "A")
                ptr[1] = UInt8(ascii: "B")
                ptr[2] = 0
            }
            XCTAssertEqual(s.name, "AB")
        }
        
        do {
            var s = dirent()
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
                ptr[0] = 0xFF
                ptr[1] = 0xFF
                ptr[2] = 0
            }
            XCTAssertEqual(s.name, nil)
        }
        
        do {
            var s = dirent()
            let n = MemoryLayout.ofInstance(s.d_name).size - 1
            withUnsafeMutablePointer(to: &s.d_name) { ptr in
                let ptr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
                for i in 0 ..< n {
                    ptr[i] = UInt8(ascii: "A")
                }
                ptr[n] = 0
            }
            XCTAssertEqual(s.name, String(repeating: "A", count: n))
        }
    }
    
    static var allTests = [
        ("testName", testName),
    ]
}
