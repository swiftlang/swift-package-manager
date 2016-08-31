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

class ByteStringPerfTests: XCTestCase {
    func testInitialization() {
        let listOfStrings: [String] = (0..<10).map { "This is the number: \($0)!\n" }
        let expectedTotalCount = listOfStrings.map({ $0.utf8.count }).reduce(0, combine: (+))
        measure {
            var count = 0
            let N = 10000
            for _ in 0..<N {
                for string in listOfStrings {
                    let bs = ByteString(encodingAsUTF8: string)
                    count += bs.count
                }
            }
            XCTAssertEqual(count, expectedTotalCount * N)
        }
    }
}

#endif
