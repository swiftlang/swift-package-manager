//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency

/// Delivers events to a sink one at a time, in the order they were emitted,
/// without blocking the emitter.
///
/// ``emit(_:)`` returns as soon as the event is queued; a single task drains the
/// queue and calls the sink. 
/// 
/// Because delivery is serialized, a slow sink delays the events queued behind it.
///
/// Releasing the queue cancels delivery, so any events still queued are dropped.
/// Call ``finish()`` first to wait for them.
package final class SerialEventQueue<Sink: Sendable>: Sendable {
    private typealias Event = @Sendable (Sink) -> Void

    private let events: AsyncStream<Event>.Continuation
    private let task: Task<Void, Never>

    package init(_ sink: Sink) {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        self.events = continuation

        // Captures `sink` and `stream`, never `self`, so the queue stays
        // deallocatable and `deinit` can tear this down.
        self.task = Task {
            for await event in stream {
                event(sink)
            }
        }
    }

    deinit {
        self.task.cancel()
        self.events.finish()
    }

    /// Enqueues `event`, to be delivered after every event emitted before it.
    package func emit(_ event: @escaping @Sendable (Sink) -> Void) {
        self.events.yield(event)
    }

    /// Stops accepting events and waits for the ones already emitted to be
    /// delivered. Events emitted afterwards are ignored. Calling this more than
    /// once is safe.
    package func finish() async {
        self.events.finish()
        await self.task.value
    }
}
