//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import XCTest

@_spi(SwiftPMInternal)
@testable
import Basics
import TSCBasic

final class ProgressAnimationTests: XCTestCase {
    class TrackingProgressAnimation: ProgressAnimationProtocol {
        var steps: [Int] = []

        func update(step: Int, total: Int, text: String) {
            steps.append(step)
        }

        func complete(success: Bool) {}
        func clear() {}
    }

    func testThrottledPercentProgressAnimation() {
        do {
            let tracking = TrackingProgressAnimation()
            var now = ContinuousClock().now
            let animation = ThrottledProgressAnimation(
                tracking, now: { now }, interval: .milliseconds(100),
                clock: ContinuousClock.self
            )

            // Update the animation 10 times with a 50ms interval.
            let total = 10
            for i in 0...total {
                animation.update(step: i, total: total, text: "")
                now += .milliseconds(50)
            }
            animation.complete(success: true)
            XCTAssertEqual(tracking.steps, [0, 2, 4, 6, 8, 10])
        }

        do {
            // Check that the last animation update is sent even if
            // the interval has not passed.
            let tracking = TrackingProgressAnimation()
            var now = ContinuousClock().now
            let animation = ThrottledProgressAnimation(
                tracking, now: { now }, interval: .milliseconds(100),
                clock: ContinuousClock.self
            )

            // Update the animation 10 times with a 50ms interval.
            let total = 10
            for i in 0...total - 1 {
                animation.update(step: i, total: total, text: "")
                now += .milliseconds(50)
            }
            // The next update is at 1000ms, but we are at 950ms,
            // so "step 9" is not sent yet.
            XCTAssertEqual(tracking.steps, [0, 2, 4, 6, 8])
            // After explicit "completion", the last step is flushed out.
            animation.complete(success: true)
            XCTAssertEqual(tracking.steps, [0, 2, 4, 6, 8, 9])
        }
    }
}
