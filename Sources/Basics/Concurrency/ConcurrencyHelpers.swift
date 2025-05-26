//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import Dispatch
import class Foundation.NSLock
import class Foundation.ProcessInfo
import struct Foundation.URL
import struct Foundation.UUID
import func TSCBasic.tsc_await

public enum Concurrency {
    public static var maxOperations: Int {
        Environment.current["SWIFTPM_MAX_CONCURRENT_OPERATIONS"].flatMap(Int.init) ?? ProcessInfo.processInfo
            .activeProcessorCount
    }
}

@available(*, noasync, message: "This method blocks the current thread indefinitely. Calling it from the concurrency pool can cause deadlocks")
public func unsafe_await<T>(_ body: @Sendable @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)

    let box = ThreadSafeBox<T>()
    Task {
        let localValue: T = await body()
        box.mutate { _ in localValue }
        semaphore.signal()
    }
    semaphore.wait()
    return box.get()!
}


extension DispatchQueue {
    // a shared concurrent queue for running concurrent asynchronous operations
    public static let sharedConcurrent = DispatchQueue(
        label: "swift.org.swiftpm.shared.concurrent",
        attributes: .concurrent
    )
}

extension DispatchQueue {
    package func scheduleOnQueue<T>(work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    package func asyncResult<T: Sendable>(_ callback: @escaping @Sendable (Result<T, Error>) -> Void, _ closure: @escaping @Sendable () async throws -> T) {
        let completion: @Sendable (Result<T, Error>) -> Void = {
            result in self.async {
                callback(result)
            }
        }

        Task {
            do {
                completion(.success(try await closure()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

/// A queue for running async operations with a limit on the number of concurrent tasks.
public final class AsyncOperationQueue: @unchecked Sendable {

    // This implementation is adapted from the one in swift-build,
    // modified to respect cancellation of the parent Task.
    // https://github.com/swiftlang/swift-build/blob/054f2300ad83fd1633f1b50a06b82eea9e7c6901/Sources/SWBUtil/AsyncOperationQueue.swift#L13

    typealias ID = UUID

    private let concurrentTasks: Int
    private var activeTasks: Int = 0
    private var waitingTasks: [(ID, CheckedContinuation<Void, any Error>)] = []
    private let waitingTasksLock = NSLock()

    /// Creates an `AsyncOperationQueue` with a specified number of concurrent tasks.
    /// - Parameter concurrentTasks: The maximum number of concurrent tasks that can be executed concurrently.
    public init(concurrentTasks: Int) {
        self.concurrentTasks = concurrentTasks
    }

    deinit {
        waitingTasksLock.withLock {
            if !waitingTasks.isEmpty {
                preconditionFailure("Deallocated with waiting tasks")
            }
        }
    }

    /// Executes an asynchronous operation, ensuring that the number of concurrent tasks
    // does not exceed the specified limit.
    /// - Parameter operation: The asynchronous operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: An error thrown by the operation, or a `CancellationError` if the operation is cancelled.
    public func withOperation<ReturnValue>(
        _ operation: @Sendable () async throws -> sending ReturnValue
    ) async throws -> ReturnValue {
        try await waitIfNeeded()
        defer { signalCompletion() }
        return try await operation()
    }

    private func waitIfNeeded() async throws {
        let shouldWait = waitingTasksLock.withLock {
            let shouldWait = activeTasks >= concurrentTasks
            activeTasks += 1
            return shouldWait
        }

        if shouldWait {
            let taskId = ID()

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    if !Task.isCancelled {
                        waitingTasksLock.withLock {
                            waitingTasks.append((taskId, continuation))
                        }
                    } else {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                // If the parent task is cancelled then we need to manually handle resuming the
                // continuation for the waiting task with a `CancellationError`.
                self.waitingTasksLock.withLock {
                    if let taskIndex = self.waitingTasks.firstIndex(where: { $0.0 == taskId }) {
                        let task = self.waitingTasks.remove(at: taskIndex)
                        task.1.resume(throwing: CancellationError())
                    }
                }
            }
        }
    }

    private func signalCompletion() {
        let continuationToResume = waitingTasksLock.withLock {
            activeTasks -= 1
            return waitingTasks.popLast()?.1
        }

        continuationToResume?.resume()
    }
}