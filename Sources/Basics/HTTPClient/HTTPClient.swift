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
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.NSError
import class Foundation.NSLock
import class Foundation.OperationQueue
import struct Foundation.URL
import struct Foundation.UUID
import TSCBasic

#if canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

public enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case badResponseStatusCode(Int)
    case circuitBreakerTriggered
    case responseTooLarge(Int64)
    case downloadError(String)
}

// MARK: - HTTPClient

public struct HTTPClient: Cancellable {
    public typealias Configuration = HTTPClientConfiguration
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias Handler = (Request, ProgressHandler?, @escaping (Result<Response, Error>) -> Void) -> Void
    public typealias ProgressHandler = (_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void
    public typealias CompletionHandler = (Result<HTTPClientResponse, Error>) -> Void

    public var configuration: HTTPClientConfiguration
    private let underlying: Handler

    /// DispatchSemaphore to restrict concurrent operations on manager.
    private let concurrencySemaphore: DispatchSemaphore
    /// OperationQueue to park pending requests
    private let requestsQueue: OperationQueue

    // tracks outstanding requests for cancellation
    private var outstandingRequests = ThreadSafeKeyValueStore<UUID, (url: URL, completion: CompletionHandler, progress: ProgressHandler?, queue: DispatchQueue)>()

    // static to share across instances of the http client
    private static var hostsErrorsLock = NSLock()
    private static var hostsErrors = [String: [Date]]()

    public init(configuration: HTTPClientConfiguration = .init(), handler: Handler? = nil) {
        self.configuration = configuration
        // FIXME: inject platform specific implementation here
        self.underlying = handler ?? URLSessionHTTPClient().execute

        // this queue and semaphore is used to limit the amount of concurrent http requests taking place
        // the default max number of request chosen to match Concurrency.maxOperations which is the number of active CPUs
        let maxConcurrentRequests = configuration.maxConcurrentRequests ?? Concurrency.maxOperations
        self.requestsQueue = OperationQueue()
        self.requestsQueue.name = "org.swift.swiftpm.http-client"
        self.requestsQueue.maxConcurrentOperationCount = maxConcurrentRequests
        self.concurrencySemaphore = DispatchSemaphore(value: maxConcurrentRequests)
    }

    /// Execute an HTTP request asynchronously
    ///
    /// - Parameters:
    ///   - request: The `HTTPClientRequest` to perform.
    ///   - observabilityScope: the observability scope to emit diagnostics on
    ///   - progress: A progress handler to handle progress for example for downloads
    ///   - completion: A completion handler to be notified of the completion of the request.
    public func execute(
        _ request: Request,
        observabilityScope: ObservabilityScope? = nil,
        progress: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        // merge configuration
        var request = request
        if request.options.callbackQueue == nil {
            request.options.callbackQueue = self.configuration.callbackQueue
        }
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
        if let authorization = request.options.authorizationProvider?(request.url), !request.headers.contains("Authorization") {
            request.headers.add(name: "Authorization", value: authorization)
        }
        // execute
        guard let callbackQueue = request.options.callbackQueue else {
            return completion(.failure(InternalError("unknown callback queue")))
        }
        self._execute(
            request: request,
            requestNumber: 0,
            observabilityScope: observabilityScope,
            progress: progress.map { handler in
                { received, expected in
                    // call back on the requested queue
                    callbackQueue.async {
                        handler(received, expected)
                    }
                }
            },
            completion: { result in
                // call back on the requested queue
                callbackQueue.async {
                    completion(result)
                }
            }
        )
    }

    /// Cancel any outstanding requests
    public func cancel(deadline: DispatchTime) throws {
        let outstanding = self.outstandingRequests.clear()
        for (_, callback, _, queue) in outstanding.values {
            queue.async {
                callback(.failure(CancellationError()))
            }
        }
    }

    private func _execute(
        request: Request,
        requestNumber: Int,
        observabilityScope: ObservabilityScope?,
        progress: ProgressHandler?,
        completion: @escaping CompletionHandler
    ) {
        // records outstanding requests for cancellation purposes
        guard let callbackQueue = request.options.callbackQueue else {
            return completion(.failure(InternalError("unknown callback queue")))
        }
        let requestKey = UUID()
        self.outstandingRequests[requestKey] = (url: request.url, completion: completion, progress: progress, queue: callbackQueue)

        // wrap completion handler with concurrency control cleanup
        let originalCompletion = completion
        let completion: CompletionHandler = { result in
            // free concurrency control semaphore
            self.concurrencySemaphore.signal()
            // cancellation support
            // if the callback is no longer on the pending lists it has been canceled already
            // read + remove from outstanding requests atomically
            if let (_, callback, _, queue) = self.outstandingRequests.removeValue(forKey: requestKey) {
                // call back on the request queue
                queue.async { callback(result) }
            }
        }

        // we must not block the calling thread (for concurrency control) so nesting this in a queue
        self.requestsQueue.addOperation {
            // park the request thread based on the max concurrency allowed
            self.concurrencySemaphore.wait()

            // apply circuit breaker if necessary
            if self.shouldCircuitBreak(request: request) {
                observabilityScope?.emit(warning: "Circuit breaker triggered for \(request.url)")
                return completion(.failure(HTTPClientError.circuitBreakerTriggered))
            }

            // call underlying handler
            self.underlying(
                request,
                { received, expected in
                    if let max = request.options.maximumResponseSizeInBytes {
                        guard received < max else {
                            // FIXME: cancel the request?
                            return completion(.failure(HTTPClientError.responseTooLarge(received)))
                        }
                    }
                    progress?(received, expected)
                },
                { result in
                    // handle result
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let response):
                        // record host errors for circuit breaker
                        self.recordErrorIfNecessary(response: response, request: request)
                        // handle retry strategy
                        if let retryDelay = self.shouldRetry(response: response, request: request, requestNumber: requestNumber) {
                            observabilityScope?.emit(warning: "\(request.url) failed, retrying in \(retryDelay)")
                            // free concurrency control semaphore and outstanding request,
                            // since we re-submitting the request with the original completion handler
                            // using the wrapped completion handler may lead to starving the max concurrent requests
                            self.concurrencySemaphore.signal()
                            self.outstandingRequests[requestKey] = nil
                            // TODO: dedicated retry queue?
                            return self.configuration.callbackQueue.asyncAfter(deadline: .now() + retryDelay) {
                                self._execute(request: request, requestNumber: requestNumber + 1, observabilityScope: observabilityScope, progress: progress, completion: originalCompletion)
                            }
                        }
                        // check for valid response codes
                        if let validResponseCodes = request.options.validResponseCodes, !validResponseCodes.contains(response.statusCode) {
                            return completion(.failure(HTTPClientError.badResponseStatusCode(response.statusCode)))
                        }
                        completion(.success(response))
                    }
                }
            )
        }
    }

    private func shouldRetry(response: Response, request: Request, requestNumber: Int) -> DispatchTimeInterval? {
        guard let strategy = request.options.retryStrategy, response.statusCode >= 500 else {
            return .none
        }

        switch strategy {
        case .exponentialBackoff(let maxAttempts, let delay):
            guard requestNumber < maxAttempts - 1 else {
                return .none
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
            Self.hostsErrorsLock.withLock {
                // Avoid copy-on-write: remove entry from dictionary before mutating
                var errors = Self.hostsErrors.removeValue(forKey: host) ?? []
                errors.append(Date())
                Self.hostsErrors[host] = errors
            }
        }
    }

    private func shouldCircuitBreak(request: Request) -> Bool {
        guard let strategy = request.options.circuitBreakerStrategy else {
            return false
        }

        switch strategy {
        case .hostErrors(let maxErrors, let age):
            if let host = request.url.host, let errors = (Self.hostsErrorsLock.withLock { Self.hostsErrors[host] }) {
                if errors.count >= maxErrors, let lastError = errors.last, let age = age.timeInterval() {
                    return Date().timeIntervalSince(lastError) <= age
                } else if errors.count >= maxErrors {
                    // reset aged errors
                    Self.hostsErrorsLock.withLock {
                        Self.hostsErrors[host] = nil
                    }
                }
            }
            return false
        }
    }
}

public extension HTTPClient {
    func head(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), observabilityScope: ObservabilityScope? = .none, completion: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .head, url: url, headers: headers, body: nil, options: options), observabilityScope: observabilityScope, completion: completion)
    }

    func get(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), observabilityScope: ObservabilityScope? = .none, completion: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .get, url: url, headers: headers, body: nil, options: options), observabilityScope: observabilityScope, completion: completion)
    }

    func put(_ url: URL, body: Data?, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), observabilityScope: ObservabilityScope? = .none, completion: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .put, url: url, headers: headers, body: body, options: options), observabilityScope: observabilityScope, completion: completion)
    }

    func post(_ url: URL, body: Data?, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), observabilityScope: ObservabilityScope? = .none, completion: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .post, url: url, headers: headers, body: body, options: options), observabilityScope: observabilityScope, completion: completion)
    }

    func delete(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), observabilityScope: ObservabilityScope? = .none, completion: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .delete, url: url, headers: headers, body: nil, options: options), observabilityScope: observabilityScope, completion: completion)
    }
}

// MARK: - HTTPClientConfiguration

public typealias HTTPClientAuthorizationProvider = (URL) -> String?

public struct HTTPClientConfiguration {
    public var requestHeaders: HTTPClientHeaders?
    public var requestTimeout: DispatchTimeInterval?
    public var authorizationProvider: HTTPClientAuthorizationProvider?
    public var retryStrategy: HTTPClientRetryStrategy?
    public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
    public var maxConcurrentRequests: Int?
    public var callbackQueue: DispatchQueue

    public init() {
        self.requestHeaders = .none
        self.requestTimeout = .none
        self.authorizationProvider = .none
        self.retryStrategy = .none
        self.circuitBreakerStrategy = .none
        self.maxConcurrentRequests = .none
        self.callbackQueue = .sharedConcurrent
    }
}

public enum HTTPClientRetryStrategy {
    case exponentialBackoff(maxAttempts: Int, baseDelay: DispatchTimeInterval)
}

public enum HTTPClientCircuitBreakerStrategy {
    case hostErrors(maxErrors: Int, age: DispatchTimeInterval)
}
