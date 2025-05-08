//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
import Testing

struct DispatchTimeTests {
    @Test
    func differencePositive() {
        let point: DispatchTime = .now()
        let future: DispatchTime = point + .seconds(10)

        let diff1: DispatchTimeInterval = point.distance(to: future)
        #expect(diff1.seconds() == 10)

        let diff2: DispatchTimeInterval = future.distance(to: point)
        #expect(diff2.seconds() == -10)
    }

    @Test
    func differenceNegative() {
        let point: DispatchTime = .now()
        let past: DispatchTime = point - .seconds(10)

        let diff1: DispatchTimeInterval = point.distance(to: past)
        #expect(diff1.seconds() == -10)

        let diff2: DispatchTimeInterval = past.distance(to: point)
        #expect(diff2.seconds() == 10)
    }
}
