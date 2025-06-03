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
                            // A task may have completed since we initially checked if we should wait. Check again in this locked
                            // section and if we can start it, remove it from the waiting tasks and start it immediately.
                            if waitingTasks.count >= concurrentTasks {
                                waitingTasks[index] = .waiting(taskId, continuation)
                                return nil
                            } else {
                                waitingTasks.remove(at: index)
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
                    case .creating, .running:
                        // If the task was still being created, mark it as cancelled in `waitingTasks` so that
                        // the handler for `withCheckedThrowingContinuation` can immediately cancel it.
                        self.waitingTasks[taskIndex] = .cancelled(taskId)
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

            // Remove the completed task from the list to decrement the active task count.
            if let taskIndex = self.waitingTasks.firstIndex(where: { $0.id == taskId }) {
                waitingTasks.remove(at: taskIndex)
            }

            // We cannot remove elements from `waitingTasks` while iterating over it, so we make
            // a pass to collect operations and then apply them after the loop.
            func createTaskListOperations() -> (CollectionDifference<WorkTask>?, WaitingContinuation?) {
                var changes: [CollectionDifference<WorkTask>.Change] = []
                for (index, task) in waitingTasks.enumerated() {
                    switch task {
                    case .running:
                        // Skip tasks that are already running, looking for the first one that is waiting or creating.
                        continue
                    case .creating:
                        // If the next task is in the process of being created, let the
                        // creation code in the `withCheckedThrowingContinuation` in `waitIfNeeded`
                        // handle starting the task.
                        break
                    case .waiting:
                        // Begin the next waiting task
                        changes.append(.remove(offset: index, element: task, associatedWith: nil))
                        return (CollectionDifference<WorkTask>(changes), task.continuation)
                    case .cancelled:
                        // If the next task is cancelled, continue removing cancelled
                        // tasks until we find one that hasn't run yet, or we exaust the list of waiting tasks.
                        changes.append(.remove(offset: index, element: task, associatedWith: nil))
                        continue
                    }
                }
                return (CollectionDifference<WorkTask>(changes), nil)
            }

            let (collectionOperations, continuation) = createTaskListOperations()
            if let operations = collectionOperations {
                guard let appliedDiff = waitingTasks.applying(operations) else {
                    preconditionFailure("Failed to apply changes to waiting tasks")
                }
                waitingTasks = appliedDiff
            }

            return continuation
        }

        continuationToResume?.resume()
    }
}
