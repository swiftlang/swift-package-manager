/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import struct Foundation.URL
import TSCBasic
import TSCUtility

#if canImport(Glibc)
import Glibc
#endif

#if os(Windows)
import CRT
#endif

public protocol HTTPClientProtocol {
    func execute(_ request: HTTPClientRequest, callback: @escaping (Result<HTTPClientResponse, Error>) -> Void)
}

public enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case badResponseStatusCode(Int)
    case circuitBreakerTriggered
}

// MARK: - HTTPClient

public struct HTTPClient: HTTPClientProtocol {
    public typealias Configuration = HTTPClientConfiguration
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias Handler = (Request, @escaping (Result<Response, Error>) -> Void) -> Void

    public var configuration: HTTPClientConfiguration
    private let diagnosticsEngine: DiagnosticsEngine?
    private let underlying: Handler

    // static to share across instances of the http client
    private static var hostsErrorsLock = Lock()
    private static var hostsErrors = [String: [Date]]()

    public init(configuration: HTTPClientConfiguration = .init(), handler: Handler? = nil, diagnosticsEngine: DiagnosticsEngine? = nil) {
        self.configuration = configuration
        self.diagnosticsEngine = diagnosticsEngine
        // FIXME: inject platform specific implementation here
        self.underlying = handler ?? URLSessionHTTPClient().execute
    }

    public func execute(_ request: Request, callback: @escaping (Result<Response, Error>) -> Void) {
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
        // add additional headers
        if let additionalHeaders = self.configuration.requestHeaders {
            additionalHeaders.forEach {
                request.headers.add($0)
            }
        }
        if request.options.addUserAgent, !request.headers.contains("User-Agent") {
            request.headers.add(name: "User-Agent", value: "SwiftPackageManager/\(Versioning.currentVersion.displayString)")
        }
        // execute
        self._execute(request: request, requestNumber: 0) { result in
            let callbackQueue = request.options.callbackQueue ?? self.configuration.callbackQueue
            callbackQueue.async {
                callback(result)
            }
        }
    }

    private func _execute(request: Request, requestNumber: Int, callback: @escaping (Result<Response, Error>) -> Void) {
        if self.shouldCircuitBreak(request: request) {
            diagnosticsEngine?.emit(warning: "Circuit breaker triggered for \(request.url)")
            return callback(.failure(HTTPClientError.circuitBreakerTriggered))
        }

        self.underlying(request) { result in
            switch result {
            case .failure(let error):
                callback(.failure(error))
            case .success(let response):
                // record host errors for circuit breaker
                self.recordErrorIfNecessary(response: response, request: request)
                // handle retry strategy
                if let retryDelay = self.shouldRetry(response: response, request: request, requestNumber: requestNumber) {
                    self.diagnosticsEngine?.emit(warning: "\(request.url) failed, retrying in \(retryDelay)")
                    // TODO: dedicated retry queue?
                    return self.configuration.callbackQueue.asyncAfter(deadline: .now() + retryDelay) {
                        self._execute(request: request, requestNumber: requestNumber + 1, callback: callback)
                    }
                }
                // check for valid response codes
                if let validResponseCodes = request.options.validResponseCodes, !validResponseCodes.contains(response.statusCode) {
                    return callback(.failure(HTTPClientError.badResponseStatusCode(response.statusCode)))
                }
                callback(.success(response))
            }
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
    func head(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), callback: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .head, url: url, headers: headers, body: nil, options: options), callback: callback)
    }

    func get(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), callback: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .get, url: url, headers: headers, body: nil, options: options), callback: callback)
    }

    func put(_ url: URL, body: Data?, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), callback: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .put, url: url, headers: headers, body: body, options: options), callback: callback)
    }

    func post(_ url: URL, body: Data?, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), callback: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .post, url: url, headers: headers, body: body, options: options), callback: callback)
    }

    func delete(_ url: URL, headers: HTTPClientHeaders = .init(), options: Request.Options = .init(), callback: @escaping (Result<Response, Error>) -> Void) {
        self.execute(Request(method: .delete, url: url, headers: headers, body: nil, options: options), callback: callback)
    }
}

// MARK: - HTTPClientConfiguration

public struct HTTPClientConfiguration {
    public var requestHeaders: HTTPClientHeaders?
    public var requestTimeout: DispatchTimeInterval?
    public var retryStrategy: HTTPClientRetryStrategy?
    public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
    public var callbackQueue: DispatchQueue

    public init() {
        self.requestHeaders = .none
        self.requestTimeout = .none
        self.retryStrategy = .none
        self.circuitBreakerStrategy = .none
        self.callbackQueue = .global()
    }
}

public enum HTTPClientRetryStrategy {
    case exponentialBackoff(maxAttempts: Int, baseDelay: DispatchTimeInterval)
}

public enum HTTPClientCircuitBreakerStrategy {
    case hostErrors(maxErrors: Int, age: DispatchTimeInterval)
}

// MARK: - HTTPClientRequest

public struct HTTPClientRequest {
    public let method: Method
    public let url: URL
    public var headers: HTTPClientHeaders
    public var body: Data?
    public var options: Options

    public init(method: Method = .get,
                url: URL,
                headers: HTTPClientHeaders = .init(),
                body: Data? = nil,
                options: Options = .init()) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.options = options
    }

    public enum Method {
        case head
        case get
        case post
        case put
        case delete
    }

    public struct Options {
        public var addUserAgent: Bool
        public var validResponseCodes: [Int]?
        public var timeout: DispatchTimeInterval?
        public var retryStrategy: HTTPClientRetryStrategy?
        public var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
        public var callbackQueue: DispatchQueue?

        public init() {
            self.addUserAgent = true
            self.validResponseCodes = .none
            self.timeout = .none
            self.retryStrategy = .none
            self.circuitBreakerStrategy = .none
            self.callbackQueue = .none
        }
    }
}

// MARK: - HTTPClientResponse

public struct HTTPClientResponse {
    public let statusCode: Int
    public let statusText: String?
    public let headers: HTTPClientHeaders
    public let body: Data?

    public init(statusCode: Int,
                statusText: String? = nil,
                headers: HTTPClientHeaders = .init(),
                body: Data? = nil) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
    }

    public func decodeBody<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = .init()) throws -> T? {
        try self.body.flatMap { try decoder.decode(type, from: $0) }
    }
}

// MARK: - HTTPClientHeaders

public struct HTTPClientHeaders {
    private var items: [Item]
    private var headers: [String: [String]]

    public init(_ items: [Item] = []) {
        self.items = items
        self.headers = items.reduce([String: [String]]()) { partial, item in
            var map = partial
            // Avoid copy-on-write: remove entry from dictionary before mutating
            var values = map.removeValue(forKey: item.name.lowercased()) ?? []
            values.append(item.value)
            map[item.name.lowercased()] = values
            return map
        }
    }

    public func contains(_ name: String) -> Bool {
        self.headers[name.lowercased()] != nil
    }

    public var count: Int {
        self.headers.count
    }

    public mutating func add(name: String, value: String) {
        self.add(Item(name: name, value: value))
    }

    public mutating func add(_ item: Item) {
        self.add([item])
    }

    public mutating func add(_ items: [Item]) {
        for item in items {
            if self.items.contains(item) {
                continue
            }
            // Avoid copy-on-write: remove entry from dictionary before mutating
            var values = self.headers.removeValue(forKey: item.name.lowercased()) ?? []
            values.append(item.value)
            self.headers[item.name.lowercased()] = values
            self.items.append(item)
        }
    }

    public mutating func merge(_ other: HTTPClientHeaders) {
        self.add(other.items)
    }

    public func get(_ name: String) -> [String] {
        self.headers[name.lowercased()] ?? []
    }

    public struct Item: Equatable {
        let name: String
        let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }
}

extension HTTPClientHeaders: Sequence {
    public func makeIterator() -> IndexingIterator<[Item]> {
        return self.items.makeIterator()
    }
}

extension HTTPClientHeaders: Equatable {
    public static func == (lhs: HTTPClientHeaders, rhs: HTTPClientHeaders) -> Bool {
        return lhs.headers == rhs.headers
    }
}

extension HTTPClientHeaders: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements.map(Item.init))
    }
}
