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

// FIXME: mark as deprecated once async/await is available
@available(*, noasync, message: "replace with async/await when available")
@inlinable
public func temp_await<T, ErrorType>(_ body: (@escaping (Result<T, ErrorType>) -> Void) -> Void) throws -> T {
    try tsc_await(body)
}

@available(*, noasync, message: "This method blocks the current thread indefinitely. Calling it from the concurrency pool can cause deadlocks")
public func unsafe_await<T>(_ body: @Sendable @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ThreadSafeBox<Result<T, Error>>()
    Task {
        let localResult: Result<T, Error>
        do {
            localResult = try await .success(body())
        } catch {
            localResult = .failure(error)
        }
        box.mutate { _ in localResult }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.get()!.get()
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

// FIXME: mark as deprecated once async/await is available
@available(*, deprecated, message: "replace with async/await when available")
@inlinable
public func temp_await<T>(_ body: (@escaping (T) -> Void) -> Void) -> T {
    tsc_await(body)
}

extension DispatchQueue {
    // a shared concurrent queue for running concurrent asynchronous operations
    public static let sharedConcurrent = DispatchQueue(
        label: "swift.org.swiftpm.shared.concurrent",
        attributes: .concurrent
    )
}

/// Bridges between potentially blocking methods that take a result completion closure and async/await
public func safe_async<T, ErrorType: Error>(
    _ body: @escaping @Sendable (@escaping @Sendable (Result<T, ErrorType>) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        // It is possible that body make block indefinitely on a lock, semaphore,
        // or similar then synchronously call the completion handler. For full safety
        // it is essential to move the execution off the swift concurrency pool
        DispatchQueue.sharedConcurrent.async {
            body {
                continuation.resume(with: $0)
            }
        }
    }
}

/// Bridges between potentially blocking methods that take a result completion closure and async/await
public func safe_async<T>(_ body: @escaping @Sendable (@escaping (Result<T, Never>) -> Void) -> Void) async -> T {
    await withCheckedContinuation { continuation in
        // It is possible that body make block indefinitely on a lock, semaphore,
        // or similar then synchronously call the completion handler. For full safety
        // it is essential to move the execution off the swift concurrency pool
        DispatchQueue.sharedConcurrent.async {
            body {
                continuation.resume(with: $0)
            }
        }
    }
}

#if !canImport(Darwin)
// As of Swift 5.7 and 5.8 swift-corelibs-foundation doesn't have `Sendable` annotations yet.
extension URL: @unchecked Sendable {}
#endif
