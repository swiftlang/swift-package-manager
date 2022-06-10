//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import SPMTestSupport
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
        let url = URL(string: "http://test")!
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
        let count = ThreadSafeBox<Int>(0)
        let lastCall = ThreadSafeBox<Date>()
        let maxAttempts = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let delay = DispatchTimeInterval.milliseconds(100)

        let brokenHandler: HTTPClient.Handler = { _, _, completion in
            let expectedDelta = pow(2.0, Double(count.get(default: 0) - 1)) * delay.timeInterval()!
            let delta = lastCall.get().flatMap { Date().timeIntervalSince($0) } ?? 0
            XCTAssertEqual(delta, expectedDelta, accuracy: 0.1)

            count.increment()
            lastCall.put(Date())
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
                XCTAssertEqual(count.get(), maxAttempts, "retries should match")
            }
            promise.fulfill()
        }

        let timeout = Double(Int(pow(2.0, Double(maxAttempts))) * delay.milliseconds()!) / 1000
        wait(for: [promise], timeout: 1.0 + timeout)
    }

    func testHostCircuitBreaker() {
        let maxErrors = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let age = DispatchTimeInterval.seconds(5)

        let host = "http://tes-\(UUID().uuidString).com"
        var httpClient = HTTPClient(handler: { _, _, completion in
            completion(.success(HTTPClient.Response(statusCode: errorCode)))
        })
        httpClient.configuration.circuitBreakerStrategy = .hostErrors(maxErrors: maxErrors, age: age)

        // make the initial errors
        do {
            let sync = DispatchGroup()
            let count = ThreadSafeBox<Int>(0)
            (0 ..< maxErrors).forEach { index in
                sync.enter()
                httpClient.get(URL(string: "\(host)/\(index)/foo")!) { result in
                    defer { sync.leave() }
                    count.increment()
                    switch result {
                    case .failure(let error):
                        XCTFail("unexpected failure \(error)")
                    case .success(let response):
                        XCTAssertEqual(response.statusCode, errorCode)
                    }
                }
            }
            XCTAssertEqual(sync.wait(timeout: .now() + .seconds(1)), .success, "should not timeout")
            XCTAssertEqual(count.get(), maxErrors, "expected results count to match")
        }

        // these should all circuit break
        let sync = DispatchGroup()
        let count = ThreadSafeBox<Int>(0)
        let total = Int.random(in: 10 ..< 20)
        (0 ..< total).forEach { index in
            sync.enter()
            httpClient.get(URL(string: "\(host)/\(index)/foo")!) { result in
                defer { sync.leave() }
                count.increment()
                switch result {
                case .failure(let error):
                    XCTAssertEqual(error as? HTTPClientError, .circuitBreakerTriggered, "expected error to match")
                case .success(let response):
                    XCTFail("unexpected success \(response)")
                }
            }
        }

        XCTAssertEqual(sync.wait(timeout: .now() + .seconds(1)), .success, "should not timeout")
        XCTAssertEqual(count.get(), total, "expected results count to match")
    }

    func testHostCircuitBreakerAging() {
        let maxErrors = 5
        let errorCode = Int.random(in: 500 ..< 600)
        let age = DispatchTimeInterval.milliseconds(100)

        let host = "http://tes-\(UUID().uuidString).com"
        var httpClient = HTTPClient(handler: { request, _, completion in
            if request.url.lastPathComponent == "error" {
                completion(.success(HTTPClient.Response(statusCode: errorCode)))
            } else if request.url.lastPathComponent == "okay" {
                completion(.success(.okay()))
            } else {
                completion(.failure(StringError("unknown request \(request.url)")))
            }
        })
        httpClient.configuration.circuitBreakerStrategy = .hostErrors(maxErrors: maxErrors, age: age)


        // make the initial errors
        do {
            let sync = DispatchGroup()
            let count = ThreadSafeBox<Int>(0)
            (0 ..< maxErrors).forEach { index in
                sync.enter()
                httpClient.get(URL(string: "\(host)/\(index)/error")!) { result in
                    defer { sync.leave() }
                    count.increment()
                    switch result {
                    case .failure(let error):
                        XCTFail("unexpected failure \(error)")
                    case .success(let response):
                        XCTAssertEqual(response.statusCode, errorCode)
                    }
                }
            }
            XCTAssertEqual(sync.wait(timeout: .now() + .seconds(1)), .success, "should not timeout")
            XCTAssertEqual(count.get(), maxErrors, "expected results count to match")
        }

        // these should not circuit break since they are deliberately aged
        let sync = DispatchGroup()
        let total = Int.random(in: 10 ..< 20)
        let count = ThreadSafeBox<Int>(0)

        (0 ..< total).forEach { index in
            sync.enter()
            // age it
            DispatchQueue.sharedConcurrent.asyncAfter(deadline: .now() + age) {
                httpClient.get(URL(string: "\(host)/\(index)/okay")!) { result in
                    defer { sync.leave() }
                    count.increment()
                    switch result {
                    case .failure(let error):
                        XCTFail("unexpected error \(error)")
                    case .success(let response):
                        XCTAssertEqual(response.statusCode, 200, "expected status code to match")
                    }
                }
            }
        }

        let timeout = DispatchTime.now() + .seconds(1) + .milliseconds(age.milliseconds()! * maxErrors)
        XCTAssertEqual(sync.wait(timeout: timeout), .success, "should not timeout")
        XCTAssertEqual(count.get(), total, "expected results count to match")
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

    func testExceedsDownloadSizeLimitProgress() throws {
        let maxSize: Int64 = 50

        let httpClient = HTTPClient(handler: { request, progress, completion in
            switch request.method {
            case .head:
                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([.init(name: "Content-Length", value: "0")])
                )))
            case .get:
                progress?(Int64(maxSize * 2), 0)
            default:
                XCTFail("method should match")
            }
        })

        var request = HTTPClient.Request(url: URL(string: "http://test")!)
        request.options.maximumResponseSizeInBytes = 10

        let promise = XCTestExpectation(description: "completed")
        httpClient.execute(request) { result in
            switch result {
            case .failure(let error):
                XCTAssertEqual(error as? HTTPClientError, .responseTooLarge(maxSize * 2), "expected error to match")
            case .success(let response):
                XCTFail("unexpected success \(response)")
            }
            promise.fulfill()
        }

        wait(for: [promise], timeout: 1)
    }

    func testMaxConcurrency() throws {
        let maxConcurrentRequests = 2
        var concurrentRequests = 0
        let concurrentRequestsLock = NSLock()

        var configuration = HTTPClient.Configuration()
        configuration.maxConcurrentRequests = maxConcurrentRequests
        let httpClient = HTTPClient(configuration: configuration, handler: { request, _, completion in
            defer {
                concurrentRequestsLock.withLock {
                    concurrentRequests -= 1
                }
            }

            concurrentRequestsLock.withLock {
                concurrentRequests += 1
                if concurrentRequests > maxConcurrentRequests {
                    XCTFail("too many concurrent requests \(concurrentRequests), expected \(maxConcurrentRequests)")
                }
            }

            completion(.success(.okay()))
        })

        let total = 1000
        let sync = DispatchGroup()
        let results = ThreadSafeArrayStore<Result<HTTPClient.Response, Error>>()
        for _ in 0 ..< total {
            sync.enter()
            httpClient.get(URL(string: "http://localhost/test")!) { result in
                defer { sync.leave() }
                results.append(result)
            }
        }

        if case .timedOut = sync.wait(timeout: .now() + .seconds(5)) {
            throw StringError("requests timed out")
        }

        XCTAssertEqual(results.count, total, "expected number of results to match")
        for result in results.get() {
            XCTAssertEqual(try? result.get().statusCode, 200, "expected '200 okay' response")
        }
    }

    func testCancel() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let cancellator = Cancellator(observabilityScope: observability.topScope)

        let total = 10
        // this DispatchGroup is used to wait for the requests to start before calling cancel
        let startGroup = DispatchGroup()
        // this DispatchGroup is used to park the delayed threads that would be cancelled
        let terminatedGroup = DispatchGroup()
        terminatedGroup.enter()
        // this DispatchGroup is used to monitor the outstanding threads that would be cancelled and completion handlers thrown away
        let outstandingGroup = DispatchGroup()

        let httpClient = HTTPClient(handler: { request, _, completion in
            print("handling \(request.url)")
            if Int(request.url.lastPathComponent)! < total / 2 {
                DispatchQueue.sharedConcurrent.async {
                    defer { startGroup.leave() }
                    print("\(request.url) okay")
                    completion(.success(.okay()))
                }
            } else {
                defer { startGroup.leave() }
                outstandingGroup.enter()
                print("\(request.url) waiting to be cancelled")
                DispatchQueue.sharedConcurrent.async {
                    defer { outstandingGroup.leave() }
                    XCTAssertEqual(.success, terminatedGroup.wait(timeout: .now() + 5), "timeout waiting on terminated signal")
                    completion(.failure(StringError("should be cancelled")))
                }
            }
        })

        cancellator.register(name: "http client", handler: httpClient)

        let finishGroup = DispatchGroup()
        let results = ThreadSafeKeyValueStore<URL, Result<HTTPClient.Response, Error>>()
        for index in 0 ..< total {
            startGroup.enter()
            finishGroup.enter()
            let url = URL(string: "http://test/\(index)")!
            httpClient.head(url) { result in
                defer { finishGroup.leave() }
                results[url] = result
            }
        }

        XCTAssertEqual(.success, startGroup.wait(timeout: .now() + 5), "timeout starting tasks")

        let cancelled = cancellator._cancel(deadline: .now() + .seconds(1))
        XCTAssertEqual(cancelled, 1, "expected to be terminated")
        XCTAssertNoDiagnostics(observability.diagnostics)
        // this releases the http handler threads that are waiting to test if the call was cancelled
        terminatedGroup.leave()

        XCTAssertEqual(.success, finishGroup.wait(timeout: .now() + 5), "timeout finishing tasks")

        XCTAssertEqual(results.count, total, "expected \(total) results")
        for (url, result) in results.get() {
            switch (Int(url.lastPathComponent)! < total / 2, result) {
            case (true, .success):
                break // as expected!
            case (true, .failure(let error)):
                XCTFail("expected success, but failed with \(type(of: error)) '\(error)'")
            case (false, .success):
                XCTFail("expected operation to be cancelled")
            case (false, .failure(let error)):
                XCTAssert(error is CancellationError, "expected error to be CancellationError, but was \(type(of: error)) '\(error)'")
            }
        }

        // wait for outstanding threads that would be cancelled and completion handlers thrown away
        XCTAssertEqual(.success, outstandingGroup.wait(timeout: .now() + .seconds(5)), "timeout waiting for outstanding tasks")
    }

    private func assertRequestHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders) {
        let noAgent = HTTPClientHeaders(headers.filter { $0.name != "User-Agent" })
        XCTAssertEqual(noAgent, expected, "expected headers to match")
    }

    private func assertResponseHeaders(_ headers: HTTPClientHeaders, expected: HTTPClientHeaders) {
        XCTAssertEqual(headers, expected, "expected headers to match")
    }
}
