//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation

@testable import Basics
import Testing

@Suite(
    .tags(
        Tag.TestSize.small,
    )
)
struct SerialEventQueueTests {
    /// A sink that records what it received, in arrival order.
    final class Recorder: Sendable {
        private let _values = ThreadSafeArrayStore<Int>()
        private let onReceive: (@Sendable (Int) -> Void)?

        init(onReceive: (@Sendable (Int) -> Void)? = .none) {
            self.onReceive = onReceive
        }

        var values: [Int] {
            self._values.get()
        }

        func receive(_ value: Int) {
            self.onReceive?(value)
            self._values.append(value)
        }
    }

    @Test
    func deliversEventsInEmissionOrder() async throws {
        let recorder = Recorder()
        let queue = SerialEventQueue(recorder)

        let expected = Array(0 ..< 1_000)
        for value in expected {
            queue.emit { $0.receive(value) }
        }

        await queue.finish()
        #expect(recorder.values == expected)
    }

    /// Emitting must not wait on the sink, even while the sink is busy.
    @Test
    func doesNotBlockTheEmitter() {
        let sinkEntered = DispatchSemaphore(value: 0)
        let sinkMayReturn = DispatchSemaphore(value: 0)
        let recorder = Recorder { _ in
            sinkEntered.signal()
            sinkMayReturn.wait()
        }
        let queue = SerialEventQueue(recorder)

        queue.emit { $0.receive(0) }
        #expect(sinkEntered.wait(timeout: .now() + 5) == .success, "sink was never called")

        // The sink is parked in its first callback. Emitting has to return anyway;
        // reaching the end of this test at all is the assertion.
        queue.emit { $0.receive(1) }
        sinkMayReturn.signal()
    }

    /// Finishing waits for everything already queued, even when the sink is slow
    /// enough that none of it could have been delivered yet.
    @Test
    func finishWaitsForQueuedEvents() async throws {
        let recorder = Recorder { value in
            if value == 0 {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let queue = SerialEventQueue(recorder)

        let expected = Array(0 ..< 100)
        for value in expected {
            queue.emit { $0.receive(value) }
        }

        await queue.finish()
        #expect(recorder.values == expected)
    }

    /// Finishing twice is safe, and the second call does not stall waiting on a
    /// delivery task that has already completed.
    @Test
    func finishIsIdempotent() async throws {
        let recorder = Recorder()
        let queue = SerialEventQueue(recorder)

        queue.emit { $0.receive(0) }
        await queue.finish()
        await queue.finish()

        #expect(recorder.values == [0])
    }

    /// Events emitted after finishing are ignored rather than delivered late.
    @Test
    func ignoresEventsEmittedAfterFinish() async throws {
        let recorder = Recorder()
        let queue = SerialEventQueue(recorder)

        queue.emit { $0.receive(0) }
        await queue.finish()

        queue.emit { $0.receive(1) }
        await queue.finish()

        #expect(recorder.values == [0])
    }
}
