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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPClientConfiguration: Sendable {
    // FIXME: this should be unified with ``AuthorizationProvider`` protocol or renamed to avoid unintended shadowing.
    public typealias AuthorizationProvider = @Sendable (URL)
        -> String?

    public init(
        requestHeaders: HTTPClientHeaders? = nil,
        requestTimeout: SendableTimeInterval? = nil,
        authorizationProvider: AuthorizationProvider? = nil,
        retryStrategy: HTTPClientRetryStrategy? = .default,
        circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy? = nil,
        maxConcurrentRequests: Int? = nil,
        maxConcurrentRequestsPerHost: Int? = nil
    ) {
        self.requestHeaders = requestHeaders
        self.requestTimeout = requestTimeout
        self.authorizationProvider = authorizationProvider
        self.retryStrategy = retryStrategy
        self.circuitBreakerStrategy = circuitBreakerStrategy
        self.maxConcurrentRequests = maxConcurrentRequests
        self.maxConcurrentRequestsPerHost = maxConcurrentRequestsPerHost
    }

    public var requestHeaders: HTTPClientHeaders?
    // FIXME: replace with `Duration` when that's available for back-deployment or minimum macOS is bumped to 13.0+
    public var requestTimeout: SendableTimeInterval?
    public var authorizationProvider: AuthorizationProvider?
    public var retryStrategy: HTTPClientRetryStrategy?
    public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
    public var maxConcurrentRequests: Int?
    public var maxConcurrentRequestsPerHost: Int?
}

public enum HTTPClientRetryStrategy: Sendable {
    case exponentialBackoff(maxAttempts: Int, baseDelay: SendableTimeInterval)

    public static let `default`: Self = .exponentialBackoff(maxAttempts: 3, baseDelay: .seconds(1))
    /// Disables retries; a `nil` strategy on a request inherits the client's instead.
    public static let never: Self = .exponentialBackoff(maxAttempts: 1, baseDelay: .seconds(0))

    private static let transientStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private static let transientURLErrorCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
    ]

    /// The delay before retrying after `outcome`, or `nil` if it isn't transient or no attempts remain.
    func retryDelay(after outcome: Result<HTTPClientResponse, Error>, requestNumber: Int) -> SendableTimeInterval? {
        guard Self.isTransient(outcome) else {
            return nil
        }
        switch self {
        case .exponentialBackoff(let maxAttempts, let baseDelay):
            guard requestNumber < maxAttempts - 1 else {
                return nil
            }
            if case .success(let response) = outcome,
               let retryAfter = response.headers.get("Retry-After").first.flatMap({ Int($0) }), retryAfter >= 0,
               !retryAfter.multipliedReportingOverflow(by: 1_000_000_000).overflow
            {
                return .seconds(retryAfter)
            }
            let ceiling = (baseDelay.milliseconds() ?? 0) << requestNumber
            return .milliseconds(Int.random(in: 0 ... max(ceiling, 0)))
        }
    }

    static func isTransient(_ outcome: Result<HTTPClientResponse, Error>) -> Bool {
        switch outcome {
        case .success(let response):
            return transientStatusCodes.contains(response.statusCode)
        case .failure(let error as URLError):
            return transientURLErrorCodes.contains(error.errorCode)
        case .failure(let error as NSError):
            return error.domain == NSURLErrorDomain && transientURLErrorCodes.contains(error.code)
        case .failure:
            return false
        }
    }
}

public enum HTTPClientCircuitBreakerStrategy: Sendable {
    case hostErrors(maxErrors: Int, age: SendableTimeInterval)
}

extension Result<HTTPClientResponse, Error> {
    /// Whether this outcome counts toward a host's errors in a circuit-breaking strategy.
    var isHostError: Bool {
        switch self {
        case .success(let response):
            response.statusCode >= 500
        case .failure:
            HTTPClientRetryStrategy.isTransient(self)
        }
    }
}
