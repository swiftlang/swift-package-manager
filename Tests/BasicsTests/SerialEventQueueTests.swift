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

        await drain(queue)
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

    /// Waits for previously emitted events to be delivered. A sentinel event is
    /// delivered only after everything emitted ahead of it, so this needs nothing
    /// from the queue beyond the ordering it already guarantees.
    private func drain(_ queue: SerialEventQueue<Recorder>) async {
        await withCheckedContinuation { continuation in
            queue.emit { _ in continuation.resume() }
        }
    }

    /// Events already enqueued are still delivered once the queue is released.
    @Test
    func drainsBufferedEventsAfterRelease() async throws {
        let recorder = Recorder()
        let expected = Array(0 ..< 100)

        do {
            let queue = SerialEventQueue(recorder)
            for value in expected {
                queue.emit { $0.receive(value) }
            }
        }

        let deadline = ContinuousClock.now + .seconds(5)
        while recorder.values != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.values == expected)
    }
}
