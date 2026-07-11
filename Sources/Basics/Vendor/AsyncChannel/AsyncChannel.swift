//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//
//
// Vendored from swift-async-algorithms to avoid a package dependency. See Vendor/README.md.
// Changes: reduced the public API of AsyncChannel to `package`.
//
//===----------------------------------------------------------------------===//

/// A channel for sending elements from one task to another with back pressure.
///
/// The `AsyncChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The back
/// pressure applied by `send(_:)` via the suspension/resume ensures that
/// the production of values does not exceed the consumption of values from iteration. This method
/// suspends after enqueuing the event and is resumed when the next call to `next()`
/// on the `Iterator` is made, or when `finish()` is called from another Task.
/// As `finish()` induces a terminal state, there is no more need for a back pressure management.
/// This function does not suspend and will finish all the pending iterations.
package final class AsyncChannel<Element: Sendable>: AsyncSequence, Sendable {
  package typealias Element = Element
  package typealias AsyncIterator = Iterator

  let storage: ChannelStorage<Element, Never>

  package init() {
    self.storage = ChannelStorage()
  }

  /// Sends an element to an awaiting iteration. This function will resume when the next call to `next()` is made
  /// or when a call to `finish()` is made from another task.
  /// If the channel is already finished then this returns immediately.
  /// If the task is cancelled, this function will resume without sending the element.
  /// Other sending operations from other tasks will remain active.
  package func send(_ element: Element) async {
    await self.storage.send(element: element)
  }

  /// Immediately resumes all the suspended operations.
  /// All subsequent calls to `next(_:)` will resume immediately.
  package func finish() {
    self.storage.finish()
  }

  package func makeAsyncIterator() -> Iterator {
    Iterator(storage: self.storage)
  }

  package struct Iterator: AsyncIteratorProtocol {
    let storage: ChannelStorage<Element, Never>

    package mutating func next() async -> Element? {
      // Although the storage can throw, its usage in the context of an `AsyncChannel` guarantees it cannot.
      // There is no public way of sending a failure to it.
      try! await self.storage.next()
    }
  }
}

@available(*, unavailable)
extension AsyncChannel.Iterator: Sendable { }
