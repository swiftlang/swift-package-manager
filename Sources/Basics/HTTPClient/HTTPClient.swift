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
import Foundation

/// `async`-friendly wrapper for HTTP clients. It allows a specific client implementation (either Foundation or
/// NIO-based) to be hidden from users of the wrapper.
public actor HTTPClient {
    public typealias Configuration = HTTPClientConfiguration
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias ProgressHandler = @Sendable (_ bytesReceived: Int64, _ totalBytes: Int64?) throws -> Void
    public typealias Implementation = @Sendable (Request, ProgressHandler?) async throws -> Response

    /// Record of errors that occurred when querying a host applied in a circuit-breaking strategy.
    private struct HostErrors {
        var numberOfErrors: Int
        var lastError: Date
    }

    /// Configuration used by ``HTTPClient`` when handling requests.
    private let configuration: HTTPClientConfiguration

    /// Underlying implementation of ``HTTPClient``.
    private let implementation: Implementation

    /// An `async`-friendly semaphore to handle limits on the number of concurrent requests.
    private let tokenBucket: TokenBucket

    /// Array of `HostErrors` values, which is used for applying a circuit-breaking strategy.
    private var hostsErrors = [String: HostErrors]()

    /// Tracks all active network request tasks.
    private var activeTasks: Set<Task<HTTPClient.Response, Error>> = []

    public init(configuration: HTTPClientConfiguration = .init(), implementation: Implementation? = nil) {
        self.configuration = configuration
        self.implementation = implementation ?? URLSessionHTTPClient().execute
        self.tokenBucket = TokenBucket(tokens: configuration.maxConcurrentRequests ?? Concurrency.maxOperations)
    }

    /// Execute an HTTP request asynchronously
    ///
    /// - Parameters:
    ///   - request: The ``HTTPClientRequest`` to perform.
    ///   - observabilityScope: the observability scope to emit diagnostics on.
    ///   - progress: A closure to handle response download progress.
    /// - Returns: A response value returned by underlying ``HTTPClient.Implementation``.
    public func execute(
        _ request: Request,
        observabilityScope: ObservabilityScope? = nil,
        progress: ProgressHandler? = nil
    ) async throws -> Response {
        // merge configuration
        var request = request
        if request.options.retryStrategy == nil {
            request.options.retryStrategy = self.configuration.retryStrategy
        }
        if request.options.circuitBreakerStrategy == nil {
            request.options.circuitBreakerStrategy = self.configuration.circuitBreakerStrategy
        }
        if request.options.timeout == nil {
            request.options.timeout = self.configuration.requestTimeout
        }
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

        if let authorization = request.options.authorizationProvider?(request.url),
           !authorization.isEmpty,
           !request.headers.contains("Authorization")
        {
            request.headers.add(name: "Authorization", value: authorization)
        }

        return try await self.executeWithStrategies(request: request, requestNumber: 0, observabilityScope, progress)
    }

    /// Cancel all in flight network reqeusts.
    public func cancel(deadline: DispatchTime) async {
        for task in activeTasks {
            task.cancel()
        }

        // Wait for tasks to complete or timeout
        while !activeTasks.isEmpty && (deadline.distance(to: .now()).nanoseconds() ?? 0) > 0 {
            await Task.yield()
        }

        // Clear out the active task list regardless of whether they completed or not
        activeTasks.removeAll()
    }

    private func executeWithStrategies(
        request: Request,
        requestNumber: Int,
        _ observabilityScope: ObservabilityScope?,
        _ progress: ProgressHandler?
    ) async throws -> Response {
        // apply circuit breaker if necessary
        if self.shouldCircuitBreak(request: request) {
            observabilityScope?.emit(warning: "Circuit breaker triggered for \(request.url)")
            throw HTTPClientError.circuitBreakerTriggered
        }

        let task = Task {
            let response = try await self.tokenBucket.withToken {
                try Task.checkCancellation()

                return try await self.implementation(request) { received, expected in
                    if let max = request.options.maximumResponseSizeInBytes {
                        guard received < max else {
                            // It's a responsibility of the underlying client implementation to cancel the request
                            // when this closure throws an error
                            throw HTTPClientError.responseTooLarge(received)
                        }
                    }

                    try progress?(received, expected)
                }
            }

            self.recordErrorIfNecessary(response: response, request: request)

            // handle retry strategy
            if let retryDelay = self.calculateRetry(
                response: response,
                request: request,
                requestNumber: requestNumber
            ), let retryDelayInNanoseconds = retryDelay.nanoseconds() {
                try Task.checkCancellation()

                observabilityScope?.emit(warning: "\(request.url) failed, retrying in \(retryDelay)")
                try await Task.sleep(nanoseconds: UInt64(retryDelayInNanoseconds))

                return try await self.executeWithStrategies(
                    request: request,
                    requestNumber: requestNumber + 1,
                    observabilityScope,
                    progress
                )
            }
            // check for valid response codes
            if let validResponseCodes = request.options.validResponseCodes,
            !validResponseCodes.contains(response.statusCode)
            {
                throw HTTPClientError.badResponseStatusCode(response.statusCode)
            } else {
                return response
            }
        }

        activeTasks.insert(task)
        defer { activeTasks.remove(task) }

        return try await task.value
    }

    private func calculateRetry(response: Response, request: Request, requestNumber: Int) -> SendableTimeInterval? {
        guard let strategy = request.options.retryStrategy, response.statusCode >= 500 else {
            return nil
        }

        switch strategy {
        case .exponentialBackoff(let maxAttempts, let delay):
            guard requestNumber < maxAttempts - 1 else {
                return nil
            }
            let exponential = Int(min(pow(2.0, Double(requestNumber)), Double(Int.max)))
            let delayMilli = exponential.multipliedReportingOverflow(by: delay.milliseconds() ?? 0).partialValue
            let jitterMilli = Int.random(in: 1 ... 10)
            return .milliseconds(delayMilli + jitterMilli)
        }
    }

    private func recordErrorIfNecessary(response: Response, request: Request) {
        guard let strategy = request.options.circuitBreakerStrategy, response.statusCode >= 500 else {
            return
        }

        switch strategy {
        case .hostErrors:
            guard let host = request.url.host else {
                return
            }
            // Avoid copy-on-write: remove entry from dictionary before mutating
            let hostErrors: HostErrors
            if var errors = self.hostsErrors.removeValue(forKey: host) {
                errors.numberOfErrors += 1
                errors.lastError = Date()
                hostErrors = errors
            } else {
                hostErrors = HostErrors(numberOfErrors: 1, lastError: Date())
            }
            self.hostsErrors[host] = hostErrors
        }
    }

    private func shouldCircuitBreak(request: Request) -> Bool {
        guard let strategy = request.options.circuitBreakerStrategy else {
            return false
        }

        switch strategy {
        case .hostErrors(let maxErrors, let age):
            if let host = request.url.host, let errors = self.hostsErrors[host] {
                if errors.numberOfErrors >= maxErrors, let age = age.timeInterval() {
                    return Date().timeIntervalSince(errors.lastError) <= age
                } else if errors.numberOfErrors >= maxErrors {
                    // reset aged errors
                    self.hostsErrors[host] = nil
                }
            }
            return false
        }
    }
}

extension HTTPClient {
    public func head(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .head, url: url, headers: headers, body: nil, options: options)
        )
    }

    public func get(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .get, url: url, headers: headers, body: nil, options: options)
        )
    }

    public func put(
        _ url: URL,
        body: Data?,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .put, url: url, headers: headers, body: body, options: options)
        )
    }

    public func post(
        _ url: URL,
        body: Data?,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .post, url: url, headers: headers, body: body, options: options)
        )
    }

    public func delete(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init()
    ) async throws -> Response {
        try await self.execute(
            Request(method: .delete, url: url, headers: headers, body: nil, options: options)
        )
    }

    public func download(
        _ url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Request.Options = .init(),
        progressHandler: ProgressHandler? = nil,
        fileSystem: FileSystem,
        destination: AbsolutePath,
        observabilityScope: ObservabilityScope? = .none
    ) async throws -> Response {
        try await self.execute(
            Request(
                kind: .download(fileSystem: fileSystem, destination: destination),
                url: url,
                headers: headers,
                body: nil,
                options: options
            ),
            observabilityScope: observabilityScope,
            progress: progressHandler
        )
    }
}
