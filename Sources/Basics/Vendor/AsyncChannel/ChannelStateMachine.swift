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
// Changes: none.
//
//===----------------------------------------------------------------------===//
import OrderedCollections

struct ChannelStateMachine<Element: Sendable, Failure: Error>: Sendable {
  private struct SuspendedProducer: Hashable, Sendable {
    let id: UInt64
    let continuation: UnsafeContinuation<Void, Never>?
    let element: Element?

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }

    static func == (_ lhs: SuspendedProducer, _ rhs: SuspendedProducer) -> Bool {
      return lhs.id == rhs.id
    }

    static func placeHolder(id: UInt64) -> SuspendedProducer {
      SuspendedProducer(id: id, continuation: nil, element: nil)
    }
  }

  private struct SuspendedConsumer: Hashable, Sendable {
    let id: UInt64
    let continuation: UnsafeContinuation<Element?, any Error>?

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }

    static func == (_ lhs: SuspendedConsumer, _ rhs: SuspendedConsumer) -> Bool {
      return lhs.id == rhs.id
    }

    static func placeHolder(id: UInt64) -> SuspendedConsumer {
      SuspendedConsumer(id: id, continuation: nil)
    }
  }

  private enum Termination {
    case finished
    case failed(Error)
  }

  private enum State: Sendable {
    case channeling(
      suspendedProducers: OrderedSet<SuspendedProducer>,
      cancelledProducers: Set<SuspendedProducer>,
      suspendedConsumers: OrderedSet<SuspendedConsumer>,
      cancelledConsumers: Set<SuspendedConsumer>
    )
    case terminated(Termination)
  }

  private var state: State = .channeling(suspendedProducers: [], cancelledProducers: [], suspendedConsumers: [], cancelledConsumers: [])

  enum SendAction {
    case resumeConsumer(continuation: UnsafeContinuation<Element?, any Error>?)
    case suspend
  }

  mutating func send() -> SendAction {
    switch self.state {
      case .channeling(_, _, let suspendedConsumers, _) where suspendedConsumers.isEmpty:
        // we are idle or waiting for consumers, we have to suspend the producer
        return .suspend

      case .channeling(let suspendedProducers, let cancelledProducers, var suspendedConsumers, let cancelledConsumers):
        // we are waiting for producers, we can resume the first available consumer
        let suspendedConsumer = suspendedConsumers.removeFirst()
        self.state = .channeling(
          suspendedProducers: suspendedProducers,
          cancelledProducers: cancelledProducers,
          suspendedConsumers: suspendedConsumers,
          cancelledConsumers: cancelledConsumers
        )
        return .resumeConsumer(continuation: suspendedConsumer.continuation)

      case .terminated:
        return .resumeConsumer(continuation: nil)
    }
  }

  enum SendSuspendedAction {
    case resumeProducer
    case resumeProducerAndConsumer(continuation: UnsafeContinuation<Element?, any Error>?)
  }

  mutating func sendSuspended(
    continuation: UnsafeContinuation<Void, Never>,
    element: Element,
    producerID: UInt64
  ) -> SendSuspendedAction? {
    switch self.state {
      case .channeling(var suspendedProducers, var cancelledProducers, var suspendedConsumers, let cancelledConsumers):
        let suspendedProducer = SuspendedProducer(id: producerID, continuation: continuation, element: element)
        if let _ = cancelledProducers.remove(suspendedProducer) {
          // the producer was already cancelled, we resume it
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeProducer
        }

        if suspendedConsumers.isEmpty {
          // we are idle or waiting for consumers
          // we stack the incoming producer in a suspended state
          suspendedProducers.append(suspendedProducer)
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .none
        } else {
          // we are waiting for producers
          // we resume the first consumer
          let suspendedConsumer = suspendedConsumers.removeFirst()
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeProducerAndConsumer(continuation: suspendedConsumer.continuation)
        }

      case .terminated:
        return .resumeProducer
    }
  }

  enum SendCancelledAction {
    case none
    case resumeProducer(continuation: UnsafeContinuation<Void, Never>?)
  }

  mutating func sendCancelled(producerID: UInt64) -> SendCancelledAction {
    switch self.state {
      case .channeling(var suspendedProducers, var cancelledProducers, let suspendedConsumers, let cancelledConsumers):
        // the cancelled producer might be part of the waiting list
        let placeHolder = SuspendedProducer.placeHolder(id: producerID)

        if let removed = suspendedProducers.remove(placeHolder) {
          // the producer was cancelled after being added to the suspended ones, we resume it
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeProducer(continuation: removed.continuation)
        }

        // the producer was cancelled before being added to the suspended ones
        cancelledProducers.update(with: placeHolder)
        self.state = .channeling(
          suspendedProducers: suspendedProducers,
          cancelledProducers: cancelledProducers,
          suspendedConsumers: suspendedConsumers,
          cancelledConsumers: cancelledConsumers
        )
        return .none

      case .terminated:
        return .none
    }
  }

  enum FinishAction {
    case none
    case resumeProducersAndConsumers(
      producerSontinuations: [UnsafeContinuation<Void, Never>?],
      consumerContinuations: [UnsafeContinuation<Element?, any Error>?]
    )
  }

  mutating func finish(error: Failure?) -> FinishAction {
    switch self.state {
      case .channeling(let suspendedProducers, _, let suspendedConsumers, _):
        // no matter if we are idle, waiting for producers or waiting for consumers, we resume every thing that is suspended
        if let error {
          if suspendedConsumers.isEmpty {
            self.state = .terminated(.failed(error))
          } else {
            self.state = .terminated(.finished)
          }
        } else {
          self.state = .terminated(.finished)
        }
        return .resumeProducersAndConsumers(
          producerSontinuations: suspendedProducers.map { $0.continuation },
          consumerContinuations: suspendedConsumers.map { $0.continuation }
        )

      case .terminated:
        return .none
    }
  }

  enum NextAction {
    case resumeProducer(continuation: UnsafeContinuation<Void, Never>?, result: Result<Element?, Error>)
    case suspend
  }

  mutating func next() -> NextAction {
    switch self.state {
      case .channeling(let suspendedProducers, _, _, _) where suspendedProducers.isEmpty:
        // we are idle or waiting for producers, we must suspend
        return .suspend

      case .channeling(var suspendedProducers, let cancelledProducers, let suspendedConsumers, let cancelledConsumers):
        // we are waiting for consumers, we can resume the first awaiting producer
        let suspendedProducer = suspendedProducers.removeFirst()
        self.state = .channeling(
          suspendedProducers: suspendedProducers,
          cancelledProducers: cancelledProducers,
          suspendedConsumers: suspendedConsumers,
          cancelledConsumers: cancelledConsumers
        )
        return .resumeProducer(
          continuation: suspendedProducer.continuation,
          result: .success(suspendedProducer.element)
        )

      case .terminated(.failed(let error)):
        self.state = .terminated(.finished)
        return .resumeProducer(continuation: nil, result: .failure(error))

      case .terminated:
        return .resumeProducer(continuation: nil, result: .success(nil))
    }
  }

  enum NextSuspendedAction {
    case resumeConsumer(element: Element?)
    case resumeConsumerWithError(error: Error)
    case resumeProducerAndConsumer(continuation: UnsafeContinuation<Void, Never>?, element: Element?)
  }

  mutating func nextSuspended(
    continuation: UnsafeContinuation<Element?, any Error>,
    consumerID: UInt64
  ) -> NextSuspendedAction? {
    switch self.state {
      case .channeling(var suspendedProducers, let cancelledProducers, var suspendedConsumers, var cancelledConsumers):
        let suspendedConsumer = SuspendedConsumer(id: consumerID, continuation: continuation)
        if let _ = cancelledConsumers.remove(suspendedConsumer) {
          // the consumer was already cancelled, we resume it
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeConsumer(element: nil)
        }

        if suspendedProducers.isEmpty {
          // we are idle or waiting for producers
          // we stack the incoming consumer in a suspended state
          suspendedConsumers.append(suspendedConsumer)
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .none
        } else {
          // we are waiting for consumers
          // we resume the first producer
          let suspendedProducer = suspendedProducers.removeFirst()
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeProducerAndConsumer(
            continuation: suspendedProducer.continuation,
            element: suspendedProducer.element
          )
        }

      case .terminated(.finished):
        return .resumeConsumer(element: nil)

      case .terminated(.failed(let error)):
        self.state = .terminated(.finished)
        return .resumeConsumerWithError(error: error)
    }
  }

  enum NextCancelledAction {
    case none
    case resumeConsumer(continuation: UnsafeContinuation<Element?, any Error>?)
  }

  mutating func nextCancelled(consumerID: UInt64) -> NextCancelledAction {
    switch self.state {
      case .channeling(let suspendedProducers, let cancelledProducers, var suspendedConsumers, var cancelledConsumers):
        // the cancelled consumer might be part of the suspended ones
        let placeHolder = SuspendedConsumer.placeHolder(id: consumerID)

        if let removed = suspendedConsumers.remove(placeHolder) {
          // the consumer was cancelled after being added to the suspended ones, we resume it
          self.state = .channeling(
            suspendedProducers: suspendedProducers,
            cancelledProducers: cancelledProducers,
            suspendedConsumers: suspendedConsumers,
            cancelledConsumers: cancelledConsumers
          )
          return .resumeConsumer(continuation: removed.continuation)
        }

        // the consumer was cancelled before being added to the suspended ones
        cancelledConsumers.update(with: placeHolder)
        self.state = .channeling(
          suspendedProducers: suspendedProducers,
          cancelledProducers: cancelledProducers,
          suspendedConsumers: suspendedConsumers,
          cancelledConsumers: cancelledConsumers
        )
        return .none

      case .terminated:
        return .none
    }
  }
}
