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

public struct LegacyHTTPClientRequest: Sendable {
    public let kind: Kind
    public let url: URL
    public var headers: HTTPClientHeaders
    public var body: Data?
    public var options: Options

    public init(
        kind: Kind,
        url: URL,
        headers: HTTPClientHeaders = .init(),
        body: Data? = nil,
        options: Options = .init()
    ) {
        self.kind = kind
        self.url = url
        self.headers = headers
        self.body = body
        self.options = options
    }

    // generic request
    public init(
        method: HTTPMethod = .get,
        url: URL,
        headers: HTTPClientHeaders = .init(),
        body: Data? = nil,
        options: Options = .init()
    ) {
        self.init(kind: .generic(method), url: url, headers: headers, body: body, options: options)
    }

    // download request
    public static func download(
        url: URL,
        headers: HTTPClientHeaders = .init(),
        options: Options = .init(),
        fileSystem: FileSystem,
        destination: AbsolutePath
    ) -> Self {
        self.init(
            kind: .download(fileSystem: fileSystem, destination: destination),
            url: url,
            headers: headers,
            body: nil,
            options: options
        )
    }

    public var method: HTTPMethod {
        switch self.kind {
        case .generic(let method):
            return method
        case .download:
            return .get
        }
    }

    public typealias FileMoveCompletion = @Sendable (Error?)
        -> Void

    public enum Kind: Sendable {
        case generic(HTTPMethod)
        case download(fileSystem: FileSystem, destination: AbsolutePath)
    }

    public struct Options: Sendable {
        public init(
            addUserAgent: Bool = true,
            validResponseCodes: [Int]? = nil,
            timeout: DispatchTimeInterval? = nil,
            maximumResponseSizeInBytes: Int64? = nil,
            authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider? = nil,
            retryStrategy: HTTPClientRetryStrategy? = nil,
            circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy? = nil,
            callbackQueue: DispatchQueue? = nil
        ) {
            self.addUserAgent = addUserAgent
            self.validResponseCodes = validResponseCodes
            self.timeout = timeout
            self.maximumResponseSizeInBytes = maximumResponseSizeInBytes
            self.authorizationProvider = authorizationProvider
            self.retryStrategy = retryStrategy
            self.circuitBreakerStrategy = circuitBreakerStrategy
            self.callbackQueue = callbackQueue
        }

        public var addUserAgent: Bool
        public var validResponseCodes: [Int]?
        public var timeout: DispatchTimeInterval?
        public var maximumResponseSizeInBytes: Int64?
        public var authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?
        public var retryStrategy: HTTPClientRetryStrategy?
        public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
        public var callbackQueue: DispatchQueue?
    }
}
