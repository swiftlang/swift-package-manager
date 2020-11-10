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
import struct Foundation.URL
import TSCBasic
import TSCUtility

// MARK: - HTTPClient

public struct HTTPClient {
    public typealias Configuration = HTTPClientConfiguration
    public typealias Request = HTTPClientRequest
    public typealias Response = HTTPClientResponse
    public typealias Handler = (Request, @escaping (Result<Response, Error>) -> Void) -> Void

    private let configuration: HTTPClientConfiguration
    private let underlying: Handler

    // static to share across instances of the http client
    private static var hostsErrorsLock = Lock()
    private static var hostsErrors = [String: [Date]]()

    public init(configuration: HTTPClientConfiguration = .init(), handler: @escaping Handler) {
        self.configuration = configuration
        self.underlying = handler
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
                if let retryDelay = self.shouldRetry(response: response, request: request, requestNumber: requestNumber), #available(OSX 10.15, *) {
                    // TODO: dedicated retry queue?
                    return DispatchQueue.global().asyncAfter(deadline: DispatchTime.now().advanced(by: retryDelay)) {
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
        guard request.options.circuitBreakerStrategy != nil, let host = request.url.host, response.statusCode >= 500 else {
            return
        }

        Self.hostsErrorsLock.withLock {
            // Avoid copy-on-write: remove entry from dictionary before mutating
            var errors = Self.hostsErrors.removeValue(forKey: host) ?? []
            errors.append(Date())
            Self.hostsErrors[host] = errors
        }
    }

    private func shouldCircuitBreak(request: Request) -> Bool {
        guard let strategy = request.options.circuitBreakerStrategy, let host = request.url.host else {
            return false
        }

        switch strategy {
        case .hostErrors(let maxErrors, let age):
            if let errors = (Self.hostsErrorsLock.withLock { Self.hostsErrors[host] }) {
                if #available(OSX 10.15, *), errors.count >= maxErrors, let lastError = errors.last, let age = age.timeInterval(), lastError.distance(to: Date()) < age {
                    return true
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

extension HTTPClient {
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

public struct HTTPClientConfiguration {
    var requestHeaders: HTTPClientHeaders?
    var requestTimeout: DispatchTimeInterval?
    var retryStrategy: HTTPClientRetryStrategy?
    var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
    var callbackQueue: DispatchQueue

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

public struct HTTPClientRequest {
    let method: Method
    let url: URL
    var headers: HTTPClientHeaders
    var body: Data?
    var options: Options

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
        var addUserAgent: Bool
        var validResponseCodes: [Int]?
        var timeout: DispatchTimeInterval?
        var retryStrategy: HTTPClientRetryStrategy?
        var circuitBreakerStrategy: HTTPClientCircuitBreakerStrategy?
        var callbackQueue: DispatchQueue?

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

public struct HTTPClientResponse {
    let statusCode: Int
    let statusText: String?
    let headers: HTTPClientHeaders
    let body: Data?

    public init(statusCode: Int,
                statusText: String? = nil,
                headers: HTTPClientHeaders = .init(),
                body: Data? = nil) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
    }
}

public struct HTTPClientHeaders: Sequence, Equatable {
    // TODO: optimize
    private var headers: [Item]

    public init(_ headers: [Item] = []) {
        self.headers = headers
    }

    // TODO: optimize
    public func contains(_ name: String) -> Bool {
        self.headers.contains(where: { $0.name.lowercased() == name.lowercased() })
    }

    public var count: Int {
        self.headers.count
    }

    public mutating func add(name: String, value: String) {
        self.add(Item(name: name, value: value))
    }

    public mutating func add(_ item: Item) {
        self.headers.append(item)
    }

    // TODO: optimize
    public func get(name: String) -> [String] {
        self.headers.filter { $0.name.lowercased() == name.lowercased() }.map { $0.value }
    }

    public func makeIterator() -> IndexingIterator<[Item]> {
        self.headers.makeIterator()
    }

    public struct Item: Equatable {
        let name: String
        let value: String
    }

    public static func == (lhs: HTTPClientHeaders, rhs: HTTPClientHeaders) -> Bool {
        lhs.headers == rhs.headers
    }
}

public enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case badResponseStatusCode(Int)
    case circuitBreakerTriggered
}
