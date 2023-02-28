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

import Dispatch
import class Foundation.NSLock
import class Foundation.ProcessInfo
import struct Foundation.URL
import enum TSCBasic.ProcessEnv
import func TSCBasic.tsc_await

public enum Concurrency {
    public static var maxOperations: Int {
        ProcessEnv.vars["SWIFTPM_MAX_CONCURRENT_OPERATIONS"].flatMap(Int.init) ?? ProcessInfo.processInfo
            .activeProcessorCount
    }
}

// FIXME: mark as deprecated once async/await is available
// @available(*, deprecated, message: "replace with async/await when available")
@inlinable
public func temp_await<T, ErrorType>(_ body: (@escaping (Result<T, ErrorType>) -> Void) -> Void) throws -> T {
    try tsc_await(body)
}

// FIXME: mark as deprecated once async/await is available
// @available(*, deprecated, message: "replace with async/await when available")
@inlinable
public func temp_await<T>(_ body: (@escaping (T) -> Void) -> Void) -> T {
    tsc_await(body)
}

extension DispatchQueue {
    // a shared concurrent queue for running concurrent asynchronous operations
    public static var sharedConcurrent = DispatchQueue(
        label: "swift.org.swiftpm.shared.concurrent",
        attributes: .concurrent
    )
}

#if swift(<5.7)
extension URL: UnsafeSendable {}
#elseif !canImport(Darwin)
// As of Swift 5.7 and 5.8 swift-corelibs-foundation doesn't have `Sendable` annotations yet.
extension URL: @unchecked Sendable {}
#endif

// https://forums.swift.org/t/using-async-functions-from-synchronous-functions-and-breaking-all-the-rules/59782/3
/// Unsafely awaits an async function from a synchronous context.
/*
public func _unsafe_wait<ResultType>(_ f: @escaping () async throws -> ResultType) throws -> ResultType {
    let box = Box<ResultType>()
    let sema = DispatchSemaphore(value: 0)
    Task {
        do {
            let val = try await f()
            box.result = .success(val)
        } catch {
            box.result = .failure(error)
        }
        sema.signal()
    }
    sema.wait()

    guard let result = try box.result?.get() else {
        throw StringError("No result available")
    }
    return result
}

private class Box<ResultType> {
    var result: Result<ResultType, Error>?
}
*/
