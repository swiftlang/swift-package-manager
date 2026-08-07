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
import class Foundation.Thread
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
public func unsafe_await<T: Sendable>(_ body: @Sendable @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)

    let box = ThreadSafeBox<T?>()
    Task {
        let localValue: T = await body()
        box.mutate { _ in localValue }
        semaphore.signal()
    }
    semaphore.wait()
    return box.get()!
}

/// Runs `body` in an unstructured task that is **not** cancelled when the calling task is cancelled,
/// and suspends until it finishes.
///
/// Use this when an operation must run to completion regardless of the parent task's cancellation —
/// for example, draining a subprocess's output until the process has actually exited. Awaiting the
/// returned value is itself not a cancellation point that aborts the work early.
public func withUncancelledTask<R: Sendable>(
    returning: R.Type = R.self,
    _ body: @Sendable @escaping () async throws -> R
) async throws -> R {
    try await Task {
        try await body()
    }.value
}

public func withUncancelledTask<R: Sendable>(
    returning: R.Type = R.self,
    _ body: @Sendable @escaping () async -> R
) async -> R {
    await Task {
        await body()
    }.value
}

extension Task where Failure == Never {
    /// Runs `block` in a new thread and suspends until it finishes execution.
    ///
    /// - note: This function should be used sparingly, such as for long-running operations that may block and therefore should not be run on the Swift Concurrency thread pool. Do not use this for operations for which there may be many concurrent invocations as it could lead to thread explosion. It is meant to be a bridge to pre-existing blocking code which can't easily be converted to use Swift concurrency features.
    public static func detachNewThread(name: String? = nil, _ block: @Sendable @escaping () -> Success) async -> Success {
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                Thread.current.name = name
                return continuation.resume(returning: block())
            }
        }
    }
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
    private var waitingTasks: [WorkTask] = []
    private let waitingTasksLock = NSLock()

    fileprivate enum WorkTask {
        case creating(ID)
        case waiting(ID, WaitingContinuation)
        case running(ID)
        case cancelled(ID)

        var id: ID {
            switch self {
            case .creating(let id), .waiting(let id, _), .running(let id), .cancelled(let id):
                return id
            }
        }
    }

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
        _ operation: () async throws -> sending ReturnValue
    ) async throws -> ReturnValue {
        let taskId = try await waitIfNeeded()
        defer { signalCompletion(taskId) }
        return try await operation()
    }

    private func waitIfNeeded() async throws -> ID {
        let workTask = waitingTasksLock.withLock({
            let shouldWait = waitingTasks.count >= concurrentTasks
            let workTask = shouldWait ? WorkTask.creating(ID()) : .running(ID())
            waitingTasks.append(workTask)
            return workTask
        })

        // If we aren't creating a task that needs to wait, we're under the concurrency limit.
        guard case .creating(let taskId) = workTask else {
            return workTask.id
        }

        enum TaskAction {
            case start(WaitingContinuation)
            case cancel(WaitingContinuation)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: WaitingContinuation) -> Void in
                let action: TaskAction? = waitingTasksLock.withLock {
                    guard let index = waitingTasks.firstIndex(where: { $0.id == taskId }) else {
                        // The task may have been marked as cancelled already and then removed from
                        // waitingTasks in `signalCompletion`.
                        return .cancel(continuation)
                    }

                    switch waitingTasks[index] {
                        case .cancelled:
                            // If the task was cancelled in between creating the task cancellation handler and acquiring the lock,
                            // we should resume the continuation with a `CancellationError`.
                            waitingTasks.remove(at: index)
                            return .cancel(continuation)
                        case .creating, .running, .waiting:
                            // A task may have completed since we initially checked if we should wait. Re-check here, but
                            // count only the *running* tasks: this task is currently in `waitingTasks` as `.creating`, so
                            // counting the whole array would count it against itself and could leave it parked with no
                            // running task left to ever resume it. If a slot is free, mark this task as running in place
                            // (keeping it in `waitingTasks` so it continues to occupy a concurrency slot until it
                            // completes) and start it immediately.
                            let runningCount = waitingTasks.reduce(into: 0) { count, task in
                                if case .running = task { count += 1 }
                            }
                            if runningCount >= concurrentTasks {
                                waitingTasks[index] = .waiting(taskId, continuation)
                                return nil
                            } else {
                                waitingTasks[index] = .running(taskId)
                                return .start(continuation)
                            }
                    }
                }

                switch action {
                    case .some(.cancel(let continuation)):
                        continuation.resume(throwing: _Concurrency.CancellationError())
                    case .some(.start(let continuation)):
                        continuation.resume()
                    case .none:
                        return
                }
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
                        // If the task was still being created, mark it as cancelled in `waitingTasks` so that
                        // the handler for `withCheckedThrowingContinuation` can immediately cancel it.
                        self.waitingTasks[taskIndex] = .cancelled(taskId)
                        return nil
                    case .running:
                        // The task has already been promoted and started running, so it is no longer waiting on
                        // its continuation. Leave it in place to keep occupying its slot; it will observe the
                        // cancellation cooperatively and be removed by `signalCompletion` when it completes.
                        return nil
                    case .cancelled:
                        preconditionFailure("Attempting to cancel a task that was already cancelled")
                }
            }

            continuation?.resume(throwing: _Concurrency.CancellationError())
        }
        return workTask.id
    }

    private func signalCompletion(_ taskId: ID) {
        let continuationToResume = waitingTasksLock.withLock { () -> WaitingContinuation? in
            guard !waitingTasks.isEmpty else {
                return nil
            }

            // Remove the completed task from the list to free its concurrency slot.
            if let taskIndex = self.waitingTasks.firstIndex(where: { $0.id == taskId }) {
                waitingTasks.remove(at: taskIndex)
            }

            // Find the next task to start, removing any cancelled tombstones we pass along the way.
            var index = 0
            while index < waitingTasks.count {
                switch waitingTasks[index] {
                case .running:
                    // Already occupying a slot; keep looking for a task that hasn't started yet.
                    index += 1
                case .creating:
                    // The task is in the process of being created, i.e. it is between reserving its slot and
                    // registering its continuation. We cannot resume it here (it has no continuation yet), but we
                    // must keep looking for a waiting task behind it to promote: relying on the creating task to
                    // start itself would strand those waiting tasks if it is cancelled before it ever runs. It is
                    // safe to promote a later waiting task because the running-count re-check in `waitIfNeeded` will
                    // make this creating task park once it observes the slot is taken.
                    index += 1
                case .waiting(let id, let continuation):
                    // Promote the next waiting task to running in place so it keeps occupying a concurrency slot
                    // until it completes, then resume its continuation once the lock is released.
                    waitingTasks[index] = .running(id)
                    return continuation
                case .cancelled:
                    // Drop cancelled tasks and keep looking for one that still needs to run.
                    waitingTasks.remove(at: index)
                }
            }

            return nil
        }

        continuationToResume?.resume()
    }
}
