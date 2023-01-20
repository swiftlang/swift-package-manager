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
    public typealias Configuration = HTTPClientConfiguration
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias ProgressHandler = @Sendable (_ bytesReceived: Int64, _ totalBytes: Int64?) throws -> Void
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
        // merge configuration
        var request = request
        if request.options.authorizationProvider == nil {
            request.options.authorizationProvider = self.configuration.authorizationProvider
        }
        // add additional headers
        if let additionalHeaders = self.configuration.requestHeaders {
            additionalHeaders.forEach {
                request.headers.add($0)
            }
        }
        if request.options.addUserAgent, !request.headers.contains("User-Agent") {
            request.headers.add(name: "User-Agent", value: "SwiftPackageManager/\(SwiftVersion.current.displayString)")
        }

        if let authorization = request.options.authorizationProvider?(request.url), !request.headers.contains("Authorization") {
            request.headers.add(name: "Authorization", value: authorization)
        }
        let finalRequest = request

        let response = try await tokenBucket.withToken {
            try await self.implementation(finalRequest) { received, expected in
                if let max = finalRequest.options.maximumResponseSizeInBytes {
                    guard received < max else {
                        // It's a responsibility of the underlying client implementation to cancel the request
                        // when this closure throws an error
                        throw HTTPClientError.responseTooLarge(received)
                    }
                }

                try progress?(received, expected)
            }
        }

        // check for valid response codes
        if let validResponseCodes = request.options.validResponseCodes, !validResponseCodes.contains(response.statusCode) {
            throw HTTPClientError.badResponseStatusCode(response.statusCode)
        } else {
            return response
        }
    }
}

public extension HTTPClient {
    func head(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .head, url: url, headers: headers, body: nil, options: options)
        )
    }

    func get(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .get, url: url, headers: headers, body: nil, options: options)
        )
    }

    func put(
        _ url: URL,
        body: Data?,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .put, url: url, headers: headers, body: body, options: options)
        )
    }

    func post(
        _ url: URL,
        body: Data?,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .post, url: url, headers: headers, body: body, options: options)
        )
    }

    func delete(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .delete, url: url, headers: headers, body: nil, options: options)
        )
    }
}

#endif
