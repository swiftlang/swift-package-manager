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

class OutputByteStreamPerfTests: XCTestCase {
    func test1MBOf16ByteArrays_X100() {
        // Test writing 1MB worth of 16 byte strings.
        let bytes16 = [UInt8](repeating: 0, count: 1 << 4)
        
        measure {
            for _ in 0..<100 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream <<< bytes16
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }
    
    func test1MBOf1KByteArrays_X1000() {
        // Test writing 1MB worth of 1K byte strings.
        let bytes1k = [UInt8](repeating: 0, count: 1 << 10)
        
        measure {
            for _ in 0..<1000 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 10) {
                    stream <<< bytes1k
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOf16ByteStrings_X10() {
        // Test writing 1MB worth of 16 byte strings.
        let string16 = String(repeating: Character("X"), count: 1 << 4)
        
        measure {
            for _ in 0..<10 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream <<< string16
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOf1KByteStrings_X100() {
        // Test writing 1MB worth of 1K byte strings.
        let bytes1k = String(repeating: Character("X"), count: 1 << 10)
        
        measure {
            for _ in 0..<100 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 10) {
                    stream <<< bytes1k
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }
    
    func test1MBOfJSONEncoded16ByteStrings_X10() {
        // Test writing 1MB worth of JSON encoded 16 byte strings.
        let string16 = String(repeating: Character("X"), count: 1 << 4)
        
        measure {
            for _ in 0..<10 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream.writeJSONEscaped(string16)
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }
    
    func testFormattedJSONOutput() {
        // Test the writing of JSON formatted output using stream operators.
        struct Thing {
            var value: String
            init(_ value: String) { self.value = value }
        }
        let listOfStrings: [String] = (0..<10).map { "This is the number: \($0)!\n" }
        let listOfThings: [Thing] = listOfStrings.map(Thing.init)
        measure {
            for _ in 0..<10 {
                let stream = OutputByteStream()
                for _ in 0..<(1 << 10) {
                    for string in listOfStrings {
                        stream <<< Format.asJSON(string)
                    }
                    stream <<< Format.asJSON(listOfStrings)
                    stream <<< Format.asJSON(listOfThings, transform: { $0.value })
                }
                XCTAssertGreaterThan(stream.bytes.count, 1000)
            }
        }
    }
}

#endif
