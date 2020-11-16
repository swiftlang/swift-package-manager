/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Basics
import Foundation
#if canImport(FoundationNetworking)
// TODO: this brings OpenSSL dependency` on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif
import TSCBasic
import TSCTestSupport
import XCTest

final class URLSessionHTTPClientTest: XCTestCase {
    func testHead() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let responseStatus = 200
        let responseHeaders = [UUID().uuidString: UUID().uuidString]
        let responseBody = UUID().uuidString.data(using: .utf8)

        MockURLProtocol.onRequest("HEAD", url) { request in
            self.assertRequestHeaders(request.allHTTPHeaderFields, expected: requestHeaders)
            MockURLProtocol.respond(request, statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.head(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus)
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody)
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1.0)
    }

    func testGet() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let responseStatus = 200
        let responseHeaders = [UUID().uuidString: UUID().uuidString]
        let responseBody = UUID().uuidString.data(using: .utf8)

        MockURLProtocol.onRequest("GET", url) { request in
            self.assertRequestHeaders(request.allHTTPHeaderFields, expected: requestHeaders)
            MockURLProtocol.respond(request, statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.get(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus)
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody)
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1.0)
    }

    func testPost() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = UUID().uuidString.data(using: .utf8)

        let responseStatus = 200
        let responseHeaders = [UUID().uuidString: UUID().uuidString]
        let responseBody = UUID().uuidString.data(using: .utf8)

        MockURLProtocol.onRequest("POST", url) { request in
            // FIXME:
            XCTAssertEqual(request.httpBody, requestBody)
            self.assertRequestHeaders(request.allHTTPHeaderFields, expected: requestHeaders)
            MockURLProtocol.respond(request, statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.post(url, body: requestBody, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus)
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody)
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1.0)
    }

    func testPut() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = UUID().uuidString.data(using: .utf8)

        let responseStatus = 200
        let responseHeaders = [UUID().uuidString: UUID().uuidString]
        let responseBody = UUID().uuidString.data(using: .utf8)

        MockURLProtocol.onRequest("PUT", url) { request in
            XCTAssertEqual(request.httpBody, requestBody)
            self.assertRequestHeaders(request.allHTTPHeaderFields, expected: requestHeaders)
            MockURLProtocol.respond(request, statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.put(url, body: requestBody, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus)
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody)
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1.0)
    }

    func testDelete() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let responseStatus = 200
        let responseHeaders = [UUID().uuidString: UUID().uuidString]
        let responseBody = UUID().uuidString.data(using: .utf8)

        MockURLProtocol.onRequest("DELETE", url) { request in
            self.assertRequestHeaders(request.allHTTPHeaderFields, expected: requestHeaders)
            MockURLProtocol.respond(request, statusCode: responseStatus, headers: responseHeaders, body: responseBody)
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.delete(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus)
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody)
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1.0)
    }

    private func assertRequestHeaders(_ headers: [String: String]?, expected: HTTPClientHeaders) {
        let headers = (headers?.filter { $0.key != "User-Agent" && $0.key != "Content-Length" } ?? [])
            .flatMap { HTTPClientHeaders($0.map { .init(name: $0.key, value: $0.value) }) } ?? .init()
        XCTAssertEqual(headers, expected)
    }

    private func assertResponseHeaders(_ headers: HTTPClientHeaders, expected: [String: String]) {
        let expected = HTTPClientHeaders(expected.map { .init(name: $0.key, value: $0.value) })
        XCTAssertEqual(headers, expected)
    }
}

private class MockURLProtocol: URLProtocol {
    typealias Action = (URLRequest) -> Void

    private static var lock = Lock()
    private static var observers: [Key: Action] = [:]
    private static var requests: [Key: URLProtocol] = [:]

    static func onRequest(_ method: String, _ url: URL, completion: @escaping Action) {
        let key = Key(url, method)
        self.lock.withLock { () -> Void in
            guard !self.observers.keys.contains(key) else {
                return XCTFail("does not support multiple observers for the same url")
            }
            self.observers[key] = completion
        }
    }

    static func respond(_ request: URLRequest, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil) {
        self.respond(request.httpMethod!, request.url!, statusCode: statusCode, headers: headers, body: body)
    }

    static func respond(_ method: String, _ url: URL, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil) {
        let key = Key(url, method)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "1.1", headerFields: headers)!
        self.sendResponse(response, for: key)
        if let data = body {
            self.sendData(data, for: key)
        }
        self.sendCompletion(for: key)
    }

    private static func sendResponse(_ response: URLResponse, for key: Key) {
        guard let request = (self.lock.withLock { self.requests[key] }) else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private static func sendData(_ data: Data, for key: Key) {
        guard let request = (self.lock.withLock { self.requests[key] }) else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocol(request, didLoad: data)
    }

    private static func sendCompletion(for key: Key) {
        guard let request = (self.lock.withLock { self.requests[key] }) else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocolDidFinishLoading(request)
    }

    private static func sendError(_ error: Error, for key: Key) {
        guard let request = (self.lock.withLock { self.requests[key] }) else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocol(request, didFailWithError: error)
    }

    private struct Key: Hashable {
        let url: URL
        let method: String

        init(_ url: URL, _ method: String) {
            self.url = url
            self.method = method
        }
    }

    // MARK: - URLProtocol

    override class func canInit(with _: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let url = self.request.url, let method = self.request.httpMethod {
            let key = Key(url, method)

            Self.lock.withLock {
                Self.requests[key] = self
            }

            guard let action = (Self.lock.withLock { Self.observers[key] }) else {
                return
            }

            // read body if available
            var request = self.request
            if let bodyStream = self.request.httpBodyStream {
                bodyStream.open()
                defer { bodyStream.close() }
                let bufferSize: Int = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                var data = Data()
                while bodyStream.hasBytesAvailable {
                    let read = bodyStream.read(buffer, maxLength: bufferSize)
                    data.append(buffer, count: read)
                }
                buffer.deallocate()
                request.httpBody = data
            }

            DispatchQueue.main.async {
                action(request)
            }
        }
    }

    override func stopLoading() {
        if let url = self.request.url, let method = self.request.httpMethod {
            let key = Key(url, method)
            Self.lock.withLock {
                Self.requests[key] = nil
            }
        }
    }
}
