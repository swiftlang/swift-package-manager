/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import TestSupport


struct ByteSequence: Sequence {
    let bytes16 = [UInt8](repeating: 0, count: 1 << 4)

    func makeIterator() -> ByteSequenceIterator {
        return ByteSequenceIterator(bytes16: bytes16)
    }
}

struct ByteSequenceIterator: IteratorProtocol {
    let bytes16: [UInt8]
    var index: Int
    init(bytes16: [UInt8]) {
        self.bytes16 = bytes16
        index = 0
    }
    mutating func next() -> UInt8? {
        if index == bytes16.count { return nil }
        defer { index += 1 }
        return bytes16[index]
    }
}

class OutputByteStreamPerfTests: XCTestCasePerf {

    func test1MBOfSequence_X10() {
        let sequence = ByteSequence()
        measure {
            for _ in 0..<10 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream <<< sequence
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOfByte_X10() {
        let byte = UInt8(0)
        measure {
            for _ in 0..<10 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 20) {
                    stream <<< byte
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOfCharacters_X1() {
        measure {
            for _ in 0..<1 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 20) {
                    stream <<< Character("X")
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOf16ByteArrays_X100() {
        // Test writing 1MB worth of 16 byte strings.
        let bytes16 = [UInt8](repeating: 0, count: 1 << 4)
        
        measure {
            for _ in 0..<100 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream <<< bytes16
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }
    
    // This should give same performance as 16ByteArrays_X100.
    func test1MBOf16ByteArraySlice_X100() {
        let bytes32 = [UInt8](repeating: 0, count: 1 << 5)
        // Test writing 1MB worth of 16 byte strings.
        let bytes16 = bytes32.suffix(from: bytes32.count/2)

        measure {
            for _ in 0..<100 {
                let stream = BufferedOutputByteStream()
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
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 10) {
                    stream <<< bytes1k
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOf16ByteStrings_X10() {
        // Test writing 1MB worth of 16 byte strings.
        let string16 = String(repeating: "X", count: 1 << 4)
        
        measure {
            for _ in 0..<10 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 16) {
                    stream <<< string16
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }

    func test1MBOf1KByteStrings_X100() {
        // Test writing 1MB worth of 1K byte strings.
        let bytes1k = String(repeating: "X", count: 1 << 10)
        
        measure {
            for _ in 0..<100 {
                let stream = BufferedOutputByteStream()
                for _ in 0..<(1 << 10) {
                    stream <<< bytes1k
                }
                XCTAssertEqual(stream.bytes.count, 1 << 20)
            }
        }
    }
    
    func test1MBOfJSONEncoded16ByteStrings_X10() {
        // Test writing 1MB worth of JSON encoded 16 byte strings.
        let string16 = String(repeating: "X", count: 1 << 4)
        
        measure {
            for _ in 0..<10 {
                let stream = BufferedOutputByteStream()
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
                let stream = BufferedOutputByteStream()
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

    func testJSONToString_X100() {
        let foo = JSON.dictionary([
            "foo": .string("bar"),
            "bar": .int(2),
            "baz": .array([1, 2, 3].map(JSON.int)),
            ])

        let bar = JSON.dictionary([
            "poo": .array([foo, foo, foo]),
            "foo": .int(1),
            ])

        let baz = JSON.dictionary([
            "poo": .array([foo, bar, foo]),
            "foo": .int(1),
            ])

        let json = JSON.array((0..<100).map { _ in baz })
        measure {
            for _ in 0..<100 {
                let result = json.toString()
                XCTAssertGreaterThan(result.utf8.count, 10)
            }
        }
    }
}
