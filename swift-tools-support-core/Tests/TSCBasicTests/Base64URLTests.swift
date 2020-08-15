// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import XCTest

import TSCBasic


class Base64URLTests: XCTestCase {

    func testEncode() {
        XCTAssertEqual([UInt8]([]).base64URL(), "")
        XCTAssertEqual([UInt8]([65]).base64URL(), "QQ==")
        XCTAssertEqual([UInt8]([65, 65]).base64URL(), "QUE=")
        XCTAssertEqual([UInt8]([65, 65, 65]).base64URL(), "QUFB")
    }

    func testDecode() {
        XCTAssertEqual([UInt8](base64URL: ""), [])
        XCTAssertEqual([UInt8](base64URL: "QQ=="), [65])
        XCTAssertEqual([UInt8](base64URL: "QUE="), [65, 65])
        XCTAssertEqual([UInt8](base64URL: "QUFB"), [65, 65, 65])
        XCTAssertEqual([UInt8](base64URL: "dGVzdGluZwo="),
            [0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67, 0x0a])
    }

    func testRoundTrip() {
        for count in 1...10 {
            for _ in 0...100 {
                var data = [UInt8](repeating: 0, count: count)
                for n in 0..<count {
                    data[n] = UInt8.random(in: 0...UInt8.max)
                }
                let encoded = data.base64URL()
                let decoded = [UInt8](base64URL: encoded[encoded.startIndex...])
                XCTAssertEqual(data, decoded)
            }
        }
    }
}
