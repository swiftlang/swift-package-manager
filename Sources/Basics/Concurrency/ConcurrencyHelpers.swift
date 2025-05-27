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

    // This implementation is identical to the AsyncOperationQueue in swift-build.
    // Any modifications made here should also be made there.
    // https://github.com/swiftlang/swift-build/blob/main/Sources/SWBUtil/AsyncOperationQueue.swift#L13

    fileprivate typealias ID = UUID
    fileprivate typealias WaitingContinuation = CheckedContinuation<Void, any Error>

    private let concurrentTasks: Int
    private var activeTasks: Int = 0
    private var waitingTasks: [WaitingTask] = []
    private let waitingTasksLock = NSLock()

    fileprivate enum WaitingTask {
        case creating(ID)
        case waiting(ID, WaitingContinuation)
        case cancelled(ID)

        var id: ID {
            switch self {
            case .creating(let id), .waiting(let id, _), .cancelled(let id):
                return id
            }
        }

        var continuation: WaitingContinuation? {
            guard case .waiting(_, let continuation) = self else {
                return nil
            }
            return continuation
        }
    }

    /// Creates an `AsyncOperationQueue` with a specified number of concurrent tasks.
    /// - Parameter concurrentTasks: The maximum number of concurrent tasks that can be executed concurrently.
    public init(concurrentTasks: Int) {
        self.concurrentTasks = concurrentTasks
    }

    deinit {
        waitingTasksLock.withLock {
            if !waitingTasks.filter({ $0.continuation != nil }).isEmpty {
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
        guard waitingTasksLock.withLock({
            let shouldWait = activeTasks >= concurrentTasks
            activeTasks += 1
            return shouldWait
        }) else {
            return // Less tasks are in flight than the limit.
        }

        let taskId = ID()
        waitingTasksLock.withLock {
            waitingTasks.append(.creating(taskId))
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: WaitingContinuation) -> Void in
                let continuation: WaitingContinuation? = waitingTasksLock.withLock {
                    guard let index = waitingTasks.firstIndex(where: { $0.id == taskId }) else {
                        // If the task was cancelled in onCancelled it will have been removed from the waiting tasks list.
                        return continuation
                    }

                    // If the task was cancelled in between creating the task cancellation handler and aquiring the lock,
                    // we should resume the continuation with a `CancellationError`.
                    if case .cancelled = waitingTasks[index] {
                        return continuation
                    }

                    // Otherwise add the task to the waiting tasks list so it can be dequeued in order as tasks complete.
                    waitingTasks[index] = .waiting(taskId, continuation)
                    return nil
                }
                continuation?.resume(throwing: _Concurrency.CancellationError())
            }
        } onCancel: {
            let continuation: WaitingContinuation? = self.waitingTasksLock.withLock {
                guard let taskIndex = self.waitingTasks.firstIndex(where: { $0.id == taskId }) else {
                    return nil
                }

                switch self.waitingTasks[taskIndex] {
                    case .waiting(_, let continuation):
                        self.waitingTasks.remove(at: taskIndex)

                        // If the parent task is cancelled then we need to manually handle resuming the
                        // continuation for the waiting task with a `CancellationError`. Return the continuation
                        // here so it can be resumed once the `waitingTasksLock` is released.
                        return continuation
                    case .creating:
                        // If the task was still being created, mark it as cancelled in the queue so that
                        // withCheckedThrowingContinuation can immediately cancel it.
                        self.waitingTasks[taskIndex] = .cancelled(taskId)
                        return nil
                    case .cancelled:
                        preconditionFailure("Attempting to cancel a task that was already cancelled")
                }
            }

            continuation?.resume(throwing: _Concurrency.CancellationError())
        }
    }

    private func signalCompletion() {
        let continuationToResume = waitingTasksLock.withLock {
            // popLast until we find a continuation that is not nil, or we run out of tasks.
            while let task = waitingTasks.popLast() {
                activeTasks -= 1
                if task.continuation != nil {
                    return task.continuation
                }
            }
            return nil
        }

        continuationToResume?.resume()
    }
}
