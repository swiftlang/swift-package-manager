//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if swift(>=5.5.2)

import DequeModule

/// Type modeled after a "token bucket" pattern, which is similar to a semaphore, but is built with
/// Swift Concurrency primitives.
private actor TokenBucket {
    private var tokens: Int
    private var waiters: Deque<CheckedContinuation<Void, Never>>

    init(tokens: Int) {
        self.tokens = tokens
        self.waiters = Deque()
    }

    func withToken<ReturnType>(_ body: @Sendable () async throws -> ReturnType) async rethrows -> ReturnType {
        await self.getToken()
        defer {
            self.returnToken()
        }

        return try await body()
    }

    private func getToken() async {
        if self.tokens > 0 {
            self.tokens -= 1
            return
        }

        await withCheckedContinuation {
            self.waiters.append($0)
        }
    }

    private func returnToken() {
        if let nextWaiter = self.waiters.popFirst() {
            nextWaiter.resume()
        } else {
            self.tokens += 1
        }
    }
}

#endif
