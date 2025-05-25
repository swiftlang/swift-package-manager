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

// This implementation is based on the one in swift-build:
// https://github.com/swiftlang/swift-build/blob/054f2300ad83fd1633f1b50a06b82eea9e7c6901/Sources/SWBUtil/AsyncOperationQueue.swift#L13
public actor AsyncOperationQueue {
    private let concurrentTasks: Int
    private var activeTasks: Int = 0
    private var waitingTasks: [CheckedContinuation<Void, Never>] = []

    public init(concurrentTasks: Int) {
        self.concurrentTasks = concurrentTasks
    }

    deinit {
        if !waitingTasks.isEmpty {
            preconditionFailure("Deallocated with waiting tasks")
        }
    }

    public func withOperation<ReturnValue>(
        _ operation: @Sendable () async -> sending ReturnValue
    ) async -> ReturnValue {
        await waitIfNeeded()
        defer { signalCompletion() }
        return await operation()
    }

    public func withOperation<ReturnValue>(
        _ operation: @Sendable () async throws -> sending ReturnValue
    ) async throws -> ReturnValue {
        await waitIfNeeded()
        defer { signalCompletion() }
        return try await operation()
    }

    private func waitIfNeeded() async {
        if activeTasks >= concurrentTasks {
            await withCheckedContinuation { continuation in
                waitingTasks.append(continuation)
            }
        }

        activeTasks += 1
    }

    private func signalCompletion() {
        activeTasks -= 1

        if let continuation = waitingTasks.popLast() {
            continuation.resume()
        }
    }
}