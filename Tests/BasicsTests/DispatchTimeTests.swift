//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import XCTest

final class DispatchTimeTests: XCTestCase {
    func testDifferencePositive() {
        let point: DispatchTime = .now()
        let future: DispatchTime = point + .seconds(10)

        let diff1: DispatchTimeInterval = point.distance(to: future)
        XCTAssertEqual(diff1.seconds(), 10)

        let diff2: DispatchTimeInterval = future.distance(to: point)
        XCTAssertEqual(diff2.seconds(), -10)
    }

    func testDifferenceNegative() {
        let point: DispatchTime = .now()
        let past: DispatchTime = point - .seconds(10)

        let diff1: DispatchTimeInterval = point.distance(to: past)
        XCTAssertEqual(diff1.seconds(), -10)

        let diff2: DispatchTimeInterval = past.distance(to: point)
        XCTAssertEqual(diff2.seconds(), 10)
    }
}
