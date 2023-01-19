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

#if swift(>=5.5.2)

import _Concurrency
import Foundation
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

/// `async`-friendly wrapper for HTTP clients. It allows a specific client implementation (either Foundation or
/// NIO-based) to be hidden from users of the wrapper.
public actor HTTPClient {
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias ProgressHandler = @Sendable (_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void
    public typealias Implementation = @Sendable (Request, ProgressHandler?) async throws -> Response

    /// Configuration used by ``HTTPClient`` when handling requests.
    private let configuration: HTTPClientConfiguration

    /// Underlying implementation of ``HTTPClient``.
    private let implementation: Implementation

    ///
    private let tokenBucket: TokenBucket

    public init(configuration: HTTPClientConfiguration = .init(), implementation: Implementation? = nil) {
        self.configuration = configuration
        self.implementation = implementation ?? URLSessionHTTPClient().execute
        self.tokenBucket = TokenBucket(tokens: configuration.maxConcurrentRequests ?? Concurrency.maxOperations)
    }

    /// Execute an HTTP request asynchronously
    ///
    /// - Parameters:
    ///   - request: The ``HTTPClientRequest`` to perform.
    ///   - progress: A closure to handle response download progress.
    /// - Returns: A response value returned by underlying ``HTTPClient.Implementation``.
    public func execute(
        _ request: Request,
        progress: ProgressHandler? = nil
    ) async throws -> Response {
        let response = try await tokenBucket.withToken { try await self.implementation(request, progress) }

        // check for valid response codes
        if let validResponseCodes = request.options.validResponseCodes, !validResponseCodes.contains(response.statusCode) {
            throw HTTPClientError.badResponseStatusCode(response.statusCode)
        } else {
            return response
        }
    }
}

#endif
