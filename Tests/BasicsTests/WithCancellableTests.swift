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

import Foundation
import Testing

@testable import Basics

/// Cancels everything registered with `cancellator`. `_cancel` blocks its thread until the handlers finish, and those
/// handlers run as tasks, so it must not run on a thread of the cooperative pool or it can starve them.
private func cancel(_ cancellator: Cancellator) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            cancellator._cancel(deadline: .now() + .seconds(30))
            continuation.resume()
        }
    }
}

struct WithCancellableTests {
    @Test
    func returnsValue() async throws {
        let cancellator = Cancellator(observabilityScope: nil)
        let value = try await cancellator.withCancellable(name: "ok") { 42 }
        #expect(value == 42)
    }

    @Test
    func waitsForTaskToFinishAfterCancel() async throws {
        let cancellator = Cancellator(observabilityScope: nil)
        let started = AsyncStream<Void>.makeStream()
        let finished = ThreadSafeBox<Bool>(false)

        let work = Task {
            try await cancellator.withCancellable(name: "slow-teardown") {
                started.continuation.yield()
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                // A cancelled task can't Task.sleep, so block to simulate a child that takes a while to stop.
                Thread.sleep(forTimeInterval: 0.3)
                finished.put(true)
            }
        }
        for await _ in started.stream { break }

        await cancel(cancellator)

        // The Cancellator must not report completion before the task has finished tearing down.
        #expect(finished.get(), "_cancel returned before the cancelled task finished")
        await #expect(throws: Basics.CancellationError.self) { try await work.value }
    }

    @Test
    func propagatesCallerCancellation() async throws {
        let cancellator = Cancellator(observabilityScope: nil)
        let started = AsyncStream<Void>.makeStream()
        let sawCancellation = ThreadSafeBox<Bool>(false)

        let work = Task {
            try await cancellator.withCancellable(name: "caller-cancel") {
                started.continuation.yield()
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                sawCancellation.put(true)
            }
        }
        for await _ in started.stream { break }

        work.cancel()
        await #expect(throws: Basics.CancellationError.self) { try await work.value }
        #expect(sawCancellation.get(), "cancelling the caller did not cancel the work")
    }

    @Test
    func isRejectedWhileCancelling() async throws {
        let cancellator = Cancellator(observabilityScope: nil)
        cancellator.cancelling.put(true)
        await #expect(throws: Basics.CancellationError.self) {
            try await cancellator.withCancellable(name: "late") { 1 }
        }
    }
}
