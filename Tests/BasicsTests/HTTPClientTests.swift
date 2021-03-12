/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Basics
import TSCTestSupport
import TSCUtility
import XCTest

final class HTTPClientTest: XCTestCase {
    func testHead() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody: Data? = nil

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            completion(.success(HTTPClient.Response(statusCode: responseStatus, headers: responseHeaders, body: responseBody)))
        }

        let httpClient = HTTPClient(handler: handler)

        let promise = XCTestExpectation(description: "completed")
        httpClient.head(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus, "statusCode should match")
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody, "body should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testGet() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = UUID().uuidString.data(using: .utf8)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .get, "method should match")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            completion(.success(HTTPClient.Response(statusCode: responseStatus, headers: responseHeaders, body: responseBody)))
        }

        let httpClient = HTTPClient(handler: handler)

        let promise = XCTestExpectation(description: "completed")
        httpClient.get(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus, "statusCode should match")
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody, "body should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testPost() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = UUID().uuidString.data(using: .utf8)
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = UUID().uuidString.data(using: .utf8)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .post, "method should match")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            XCTAssertEqual(request.body, requestBody, "body should match")
            completion(.success(HTTPClient.Response(statusCode: responseStatus, headers: responseHeaders, body: responseBody)))
        }

        let httpClient = HTTPClient(handler: handler)

        let promise = XCTestExpectation(description: "completed")
        httpClient.post(url, body: requestBody, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus, "statusCode should match")
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody, "body should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testPut() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestBody = UUID().uuidString.data(using: .utf8)
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = UUID().uuidString.data(using: .utf8)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .put, "method should match")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            XCTAssertEqual(request.body, requestBody, "body should match")
            completion(.success(HTTPClient.Response(statusCode: responseStatus, headers: responseHeaders, body: responseBody)))
        }

        let httpClient = HTTPClient(handler: handler)

        let promise = XCTestExpectation(description: "completed")
        httpClient.put(url, body: requestBody, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus, "statusCode should match")
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody, "body should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testDelete() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseStatus = Int.random(in: 201 ..< 500)
        let responseHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let responseBody = UUID().uuidString.data(using: .utf8)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .delete, "method should match")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            completion(.success(HTTPClient.Response(statusCode: responseStatus, headers: responseHeaders, body: responseBody)))
        }

        let httpClient = HTTPClient(handler: handler)

        let promise = XCTestExpectation(description: "completed")
        httpClient.delete(url, headers: requestHeaders) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, responseStatus, "statusCode should match")
                self.assertResponseHeaders(response.headers, expected: responseHeaders)
                XCTAssertEqual(response.body, responseBody, "body should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testExtraHeaders() {
        let url = URL(string: "http://test")!
        let globalHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let handler: HTTPClient.Handler = { request, _, completion in
            var expectedHeaders = globalHeaders
            expectedHeaders.merge(requestHeaders)
            self.assertRequestHeaders(request.headers, expected: expectedHeaders)
            completion(.success(HTTPClient.Response(statusCode: 200)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.requestHeaders = globalHeaders

        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = true

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, 200, "statusCode should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testUserAgent() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertTrue(request.headers.contains("User-Agent"), "expecting User-Agent")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            completion(.success(HTTPClient.Response(statusCode: 200)))
        }

        let httpClient = HTTPClient(handler: handler)
        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = true

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, 200, "statusCode should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testNoUserAgent() {
        let url = URL(string: "http://test")!
        let requestHeaders = HTTPClientHeaders([HTTPClientHeaders.Item(name: UUID().uuidString, value: UUID().uuidString)])

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertFalse(request.headers.contains("User-Agent"), "expecting User-Agent")
            self.assertRequestHeaders(request.headers, expected: requestHeaders)
            completion(.success(HTTPClient.Response(statusCode: 200)))
        }

        let httpClient = HTTPClient(handler: handler)
        var request = HTTPClient.Request(method: .get, url: url, headers: requestHeaders)
        request.options.addUserAgent = false

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, 200, "statusCode should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testAuthorization() {
        let url = Foundation.URL(string: "http://test")!
        let authorization = UUID().uuidString

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertTrue(request.headers.contains("Authorization"), "expecting Authorization")
            XCTAssertEqual(request.headers.get("Authorization").first, authorization, "expecting Authorization to match")
            completion(.success(HTTPClient.Response(statusCode: 200)))
        }

        let httpClient = HTTPClient(handler: handler)
        var request = HTTPClient.Request(method: .get, url: url)

        request.options.authorizationProvider = { requestUrl in
            requestUrl == url ? authorization : nil
        }

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, 200, "statusCode should match")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testValidResponseCodes() {
        let statusCode = Int.random(in: 201 ..< 500)
        let brokenHandler: HTTPClient.Handler = { _, _, completion in
            completion(.success(HTTPClient.Response(statusCode: statusCode)))
        }

        let httpClient = HTTPClient(handler: brokenHandler)
        var request = HTTPClient.Request(method: .get, url: URL(string: "http://test")!)
        request.options.validResponseCodes = [200]

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTAssertEqual(error as? HTTPClientError, .badResponseStatusCode(statusCode), "expected error to match")
            case .success(let response):
                XCTFail("unexpected success \(response)")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testExponentialBackoff() {
        var count = 0
        var lastCall: Date?
        let maxAttempts = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let delay = DispatchTimeInterval.milliseconds(100)

        let brokenHandler: HTTPClient.Handler = { _, _, completion in
            let expectedDelta = pow(2.0, Double(count - 1)) * delay.timeInterval()!
            let delta = lastCall.flatMap { Date().timeIntervalSince($0) } ?? 0
            XCTAssertEqual(delta, expectedDelta, accuracy: 0.1)

            count += 1
            lastCall = Date()
            completion(.success(HTTPClient.Response(statusCode: errorCode)))
        }

        let httpClient = HTTPClient(handler: brokenHandler)
        var request = HTTPClient.Request(method: .get, url: URL(string: "http://test")!)
        request.options.retryStrategy = .exponentialBackoff(maxAttempts: maxAttempts, baseDelay: delay)

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTFail("unexpected error \(error)")
            case .success(let response):
                XCTAssertEqual(response.statusCode, errorCode)
                XCTAssertEqual(count, maxAttempts, "retries should match")
            }
            promise.fulfill()
        }

        let timeout = Double(Int(pow(2.0, Double(maxAttempts))) * delay.milliseconds()!) / 1000
        wait(for: [promise], timeout: timeout)
    }

    func testHostCircuitBreaker() {
        var count = 0
        let errorCode = Int.random(in: 500 ..< 600)
        let maxErrors = 5
        let age = DispatchTimeInterval.milliseconds(100)

        let brokenHandler: HTTPClient.Handler = { _, _, completion in
            count += 1
            completion(.success(HTTPClient.Response(statusCode: errorCode)))
        }

        let host = "http://tes-\(UUID().uuidString).com"
        let httpClient = HTTPClient(handler: brokenHandler)

        let sync = DispatchGroup()
        (0 ... maxErrors * 2).forEach { index in
            sync.enter()
            var request = HTTPClient.Request(method: .get, url: URL(string: "\(host)/\(index)/foo")!)
            request.options.circuitBreakerStrategy = .hostErrors(maxErrors: maxErrors, age: age)
            httpClient.execute(request) { result in
                defer { sync.leave() }
                switch result {
                case .failure(let error):
                    if index < maxErrors {
                        XCTFail("unexpected error \(error)")
                    } else {
                        XCTAssertEqual(error as? HTTPClientError, .circuitBreakerTriggered, "expected error to match")
                    }
                case .success(let response):
                    if index < maxErrors {
                        XCTAssertEqual(response.statusCode, errorCode, "expected status code to match")
                    } else {
                        XCTFail("unexpected success \(response)")
                    }
                }
            }
        }

        let timeout = DispatchTime.now() + .milliseconds(age.milliseconds()! * maxErrors)
        XCTAssertEqual(sync.wait(timeout: timeout), .success, "should not timeout")
    }

    func testHostCircuitBreakerAging() {
        var count = 0
        let errorCode = Int.random(in: 500 ..< 600)
        let maxErrors = 5
        let age = DispatchTimeInterval.milliseconds(100)

        let brokenHandler: HTTPClient.Handler = { _, _, completion in
            if count < maxErrors / 2 {
                // immediate
                completion(.success(HTTPClient.Response(statusCode: errorCode)))
            } else {
                // age it
                DispatchQueue.global().asyncAfter(deadline: .now() + age) {
                    completion(.success(HTTPClient.Response(statusCode: errorCode)))
                }
            }
            count += 1
        }

        let host = "http://tes-\(UUID().uuidString).com"
        let httpClient = HTTPClient(handler: brokenHandler)

        let sync = DispatchGroup()
        (0 ... maxErrors * 2).forEach { index in
            sync.enter()
            var request = HTTPClient.Request(method: .get, url: URL(string: "\(host)/\(index)/foo")!)
            request.options.circuitBreakerStrategy = .hostErrors(maxErrors: maxErrors, age: age)
            httpClient.execute(request) { result in
                defer { sync.leave() }
                switch result {
                case .failure(let error):
                    XCTFail("unexpected error \(error)")
                case .success(let response):
                    XCTAssertEqual(response.statusCode, errorCode, "expected status code to match")
                }
            }
        }

        let timeout = DispatchTime.now() + .milliseconds(age.milliseconds()! * maxErrors)
        XCTAssertEqual(sync.wait(timeout: timeout), .success, "should not timeout")
    }

    func testHTTPClientHeaders() {
        var headers = HTTPClientHeaders()

        let items = (1 ... Int.random(in: 10 ... 20)).map { index in HTTPClientHeaders.Item(name: "header-\(index)", value: UUID().uuidString) }
        headers.add(items)

        XCTAssertEqual(headers.count, items.count, "headers count should match")
        items.forEach { item in
            XCTAssertEqual(headers.get(item.name).first, item.value, "headers value should match")
        }

        headers.add(items.first!)
        XCTAssertEqual(headers.count, items.count, "headers count should match (no duplicates)")

        let name = UUID().uuidString
        let values = (1 ... Int.random(in: 10 ... 20)).map { "value-\($0)" }
        values.forEach { value in
            headers.add(name: name, value: value)
        }
        XCTAssertEqual(headers.count, items.count + 1, "headers count should match (no duplicates)")
        XCTAssertEqual(values, headers.get(name), "multiple headers value should match")
    }

    private func assertRequestHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders) {
        let noAgent = HTTPClientHeaders(headers.filter { $0.name != "User-Agent" })
        XCTAssertEqual(noAgent, expected, "expected headers to match")
    }

    private func assertResponseHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders) {
        XCTAssertEqual(headers, expected, "expected headers to match")
    }
}
