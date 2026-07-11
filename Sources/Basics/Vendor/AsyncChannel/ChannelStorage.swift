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
// Changes: replaced `result._rethrowGet()` with `result.get()` (the channel is only instantiated at
// Failure == Never, so the error branch is unreachable) to drop the Rethrow.swift dependency.
//
//===----------------------------------------------------------------------===//
struct ChannelStorage<Element: Sendable, Failure: Error>: Sendable {
  private let stateMachine: ManagedCriticalState<ChannelStateMachine<Element, Failure>>
  private let ids = ManagedCriticalState<UInt64>(0)

  init() {
    self.stateMachine = ManagedCriticalState(ChannelStateMachine())
  }

  func generateId() -> UInt64 {
    self.ids.withCriticalRegion { ids in
      defer { ids &+= 1 }
      return ids
    }
  }

  func send(element: Element) async {
    // check if a suspension is needed
    let action = self.stateMachine.withCriticalRegion { stateMachine in
      stateMachine.send()
    }

    switch action {
      case .suspend:
      break

      case .resumeConsumer(let continuation):
        continuation?.resume(returning: element)
        return
    }

    let producerID = self.generateId()

    await withTaskCancellationHandler {
      // a suspension is needed
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
        let action = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.sendSuspended(continuation: continuation, element: element, producerID: producerID)
        }

        switch action {
          case .none:
            break
          case .resumeProducer:
            continuation.resume()
          case .resumeProducerAndConsumer(let consumerContinuation):
            continuation.resume()
            consumerContinuation?.resume(returning: element)
        }
      }
    } onCancel: {
      let action = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.sendCancelled(producerID: producerID)
      }

      switch action {
        case .none:
          break
        case .resumeProducer(let continuation):
          continuation?.resume()
      }
    }
  }

  func finish(error: Failure? = nil) {
    let action = self.stateMachine.withCriticalRegion { stateMachine in
      stateMachine.finish(error: error)
    }

    switch action {
      case .none:
        break
      case .resumeProducersAndConsumers(let producerContinuations, let consumerContinuations):
        producerContinuations.forEach { $0?.resume() }
        if let error {
          consumerContinuations.forEach { $0?.resume(throwing: error) }
        } else {
          consumerContinuations.forEach { $0?.resume(returning: nil) }
        }
    }
  }

  func next() async throws -> Element? {
    let action = self.stateMachine.withCriticalRegion { stateMachine in
      stateMachine.next()
    }

    switch action {
      case .suspend:
        break

      case .resumeProducer(let producerContinuation, let result):
        producerContinuation?.resume()
        return try result.get()
    }

    let consumerID = self.generateId()

    return try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Element?, any Error>) in
        let action = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.nextSuspended(
            continuation: continuation,
            consumerID: consumerID
          )
        }

        switch action {
          case .none:
            break
          case .resumeConsumer(let element):
            continuation.resume(returning: element)
          case .resumeConsumerWithError(let error):
            continuation.resume(throwing: error)
          case .resumeProducerAndConsumer(let producerContinuation, let element):
            producerContinuation?.resume()
            continuation.resume(returning: element)
        }
      }
    } onCancel: {
      let action = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.nextCancelled(consumerID: consumerID)
      }

      switch action {
        case .none:
          break
        case .resumeConsumer(let continuation):
          continuation?.resume(returning: nil)
      }
    }
  }
}
