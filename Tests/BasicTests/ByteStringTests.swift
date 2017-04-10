/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

// Allow simple conversion from String, in the tests target.
extension ByteString {
    init(_ string: String) {
        self.init(encodingAsUTF8: string)
    }
}

class ByteStringTests: XCTestCase {
    func testInitializers() {
        do {
            let data: ByteString = [1]
            XCTAssertEqual(data.contents, [1])
        }

        XCTAssertEqual(ByteString([1]).contents, [1])

        XCTAssertEqual(ByteString("A").contents, [65])

        // Test ExpressibleByStringLiteral initialization.
        XCTAssertEqual(ByteString([65]), "A")
    }

    func testAccessors() {
        // Test basic accessors.
        XCTAssertEqual(ByteString([]).count, 0)
        XCTAssertEqual(ByteString([1, 2]).count, 2)
    }

    func testAsString() {
        XCTAssertEqual(ByteString("hello").asString, "hello")
        XCTAssertEqual(ByteString([0xFF,0xFF]).asString, nil)
    }

    func testDescription() {
        XCTAssertEqual(ByteString("Hello, world!").description, "<ByteString:\"Hello, world!\">")
    }
    
    func testHashable() {
        var s = Set([ByteString([1]), ByteString([2])])
        XCTAssert(s.contains(ByteString([1])))
        XCTAssert(s.contains(ByteString([2])))
        XCTAssert(!s.contains(ByteString([3])))

        // Insert a long string which tests overflow in the hash function.
        let long = ByteString([UInt8](0 ..< 100))
        XCTAssert(!s.contains(long))
        s.insert(long)
        XCTAssert(s.contains(long))
    }

    func testByteStreamable() {
        let s = BufferedOutputByteStream()
        s <<< ByteString([1, 2, 3])
        XCTAssertEqual(s.bytes, [1, 2, 3])
    }

    static var allTests = [
        ("testInitializers", testInitializers),
        ("testAccessors", testAccessors),
        ("testAsString", testAsString),
        ("testDescription", testDescription),
        ("testHashable", testHashable),
        ("testByteStreamable", testByteStreamable),
    ]
}
