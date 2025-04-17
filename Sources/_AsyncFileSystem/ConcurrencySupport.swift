
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

internal import _Concurrency
internal import class Dispatch.DispatchQueue

extension DispatchQueue {
    /// Schedules blocking synchronous work item on this ``DispatchQueue`` instance.
    /// - Parameter work: Blocking synchronous closure that should be scheduled on this queue.
    /// - Returns: Result of the `work` closure.
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
}
