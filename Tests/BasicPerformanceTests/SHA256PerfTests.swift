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

class SHA256PerfTests: XCTestCasePerf {
    func test20MBDigest_X1000() {
        let byte = "f"
        let stream = BufferedOutputByteStream()
        for _ in 0..<20000 {
            stream <<< byte
        }
        measure {
            for _ in 0..<1000 {
                XCTAssertEqual(SHA256(stream.bytes).digestString(), "23d00697ba26b4140869bab958431251e7e41982794d41b605b6a1d5dee56abf")
            }
        }
    }
}
