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

public struct HTTPClientConfiguration: Sendable {
    // FIXME: this should be unified with ``AuthorizationProvider`` protocol or renamed to avoid unintended shadowing.
    public typealias AuthorizationProvider = @Sendable (URL)
        -> String?

    public init(
        requestHeaders: HTTPClientHeaders? = nil,
        requestTimeout: SendableTimeInterval? = nil,
        authorizationProvider: AuthorizationProvider? = nil,
        retryStrategy: HTTPClientRetryStrategy? = nil,
        circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy? = nil,
        maxConcurrentRequests: Int? = nil
    ) {
        self.requestHeaders = requestHeaders
        self.requestTimeout = requestTimeout
        self.authorizationProvider = authorizationProvider
        self.retryStrategy = retryStrategy
        self.circuitBreakerStrategy = circuitBreakerStrategy
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    public var requestHeaders: HTTPClientHeaders?
    // FIXME: replace with `Duration` when that's available for back-deployment or minimum macOS is bumped to 13.0+
    public var requestTimeout: SendableTimeInterval?
    public var authorizationProvider: AuthorizationProvider?
    public var retryStrategy: HTTPClientRetryStrategy?
    public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
    public var maxConcurrentRequests: Int?
}

public enum HTTPClientRetryStrategy: Sendable {
    case exponentialBackoff(maxAttempts: Int, baseDelay: SendableTimeInterval)
}

public enum HTTPClientCircuitBreakerStrategy: Sendable {
    case hostErrors(maxErrors: Int, age: SendableTimeInterval)
}
