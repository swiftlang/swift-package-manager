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

    // MARK: - download


    func testDownloadSuccess() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let completionExpectation = XCTestExpectation(description: "completion")

            let url = URL(string: "https://downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")
            let request = HTTPClient.Request.download(url: url, fileSystem: localFileSystem, destination: destination)
            httpClient.execute(
                request,
                progress: { bytesDownloaded, totalBytesToDownload in
                    switch (bytesDownloaded, totalBytesToDownload) {
                    case (512, 1024):
                        progress50Expectation.fulfill()
                    case (1024, 1024):
                        progress100Expectation.fulfill()
                    default:
                        XCTFail("unexpected progress")
                    }
                },
                completion: { result in
                    switch result {
                    case .success:
                        XCTAssertFileExists(destination)
                        let bytes = ByteString(Array(repeating: 0xBE, count: 512) + Array(repeating: 0xEF, count: 512))
                        XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    case .failure(let error):
                        XCTFail("\(error)")
                    }
                    completionExpectation.fulfill()
                }
            )

            MockURLProtocol.onRequest(request) { _ in
                MockURLProtocol.sendResponse(statusCode: 200, headers: ["Content-Length": "1024"], for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendData(Data(repeating: 0xBE, count: 512), for: request)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockURLProtocol.sendData(Data(repeating: 0xEF, count: 512), for: request)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockURLProtocol.sendCompletion(for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }

    func testDownloadAuthenticatedSuccess() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let netrcContent = "machine protected.downloader-tests.com login anonymous password qwerty"
        let netrc = try NetrcAuthorizationWrapper(underlying: NetrcParser.parse(netrcContent))
        let authData = "anonymous:qwerty".data(using: .utf8)!
        let testAuthHeader = "Basic \(authData.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let completionExpectation = XCTestExpectation(description: "completion")

            let url = URL(string: "https://protected.downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")
            var request = HTTPClient.Request.download(url: url, fileSystem: localFileSystem, destination: destination)
            request.options.authorizationProvider = netrc.httpAuthorizationHeader(for:)
            httpClient.execute(
                request,
                progress: { bytesDownloaded, totalBytesToDownload in
                    switch (bytesDownloaded, totalBytesToDownload) {
                    case (512, 1024):
                        progress50Expectation.fulfill()
                    case (1024, 1024):
                        progress100Expectation.fulfill()
                    default:
                        XCTFail("unexpected progress")
                    }
                },
                completion: { result in
                    switch result {
                    case .success:
                        XCTAssertFileExists(destination)
                        let bytes = ByteString(Array(repeating: 0xBE, count: 512) + Array(repeating: 0xEF, count: 512))
                        XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    case .failure(let error):
                        XCTFail("\(error)")
                    }
                    completionExpectation.fulfill()
                }
            )

            MockURLProtocol.onRequest(request) { request in
                XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], testAuthHeader)
                MockURLProtocol.sendResponse(statusCode: 200, headers: ["Content-Length": "1024"], for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendData(Data(repeating: 0xBE, count: 512), for: request)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockURLProtocol.sendData(Data(repeating: 0xEF, count: 512), for: request)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockURLProtocol.sendCompletion(for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }

    func testDownloadDefaultAuthenticationSuccess() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let netrcContent = "default login default password default"
        let netrc = try NetrcAuthorizationWrapper(underlying: NetrcParser.parse(netrcContent))
        let authData = "default:default".data(using: .utf8)!
        let testAuthHeader = "Basic \(authData.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let completionExpectation = XCTestExpectation(description: "completion")

            let url = URL(string: "https://restricted.downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")
            var request = HTTPClient.Request.download(url: url, fileSystem: localFileSystem, destination: destination)
            request.options.authorizationProvider = netrc.httpAuthorizationHeader(for:)
            httpClient.execute(
                request,
                progress: { bytesDownloaded, totalBytesToDownload in
                    switch (bytesDownloaded, totalBytesToDownload) {
                    case (512, 1024):
                        progress50Expectation.fulfill()
                    case (1024, 1024):
                        progress100Expectation.fulfill()
                    default:
                        XCTFail("unexpected progress")
                    }
                },
                completion: { result in
                    switch result {
                    case .success:
                        XCTAssertFileExists(destination)
                        let bytes = ByteString(Array(repeating: 0xBE, count: 512) + Array(repeating: 0xEF, count: 512))
                        XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    case .failure(let error):
                        XCTFail("\(error)")
                    }
                    completionExpectation.fulfill()
                }
            )

            MockURLProtocol.onRequest(request) { request in
                XCTAssertEqual(request.allHTTPHeaderFields?["Authorization"], testAuthHeader)
                MockURLProtocol.sendResponse(statusCode: 200, headers: ["Content-Length": "1024"], for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendData(Data(repeating: 0xBE, count: 512), for: request)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockURLProtocol.sendData(Data(repeating: 0xEF, count: 512), for: request)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockURLProtocol.sendCompletion(for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }

    func testDownloadClientError() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let completionExpectation = XCTestExpectation(description: "completion")

            let clientError = StringError("boom")
            let url = URL(string: "https://downloader-tests.com/testClientError.zip")!
            let request = HTTPClient.Request.download(url: url, fileSystem: localFileSystem, destination: tmpdir.appending(component: "download"))
            httpClient.execute(
                request,
                progress: { bytesDownloaded, totalBytesToDownload in
                    switch (bytesDownloaded, totalBytesToDownload) {
                    case (512, 1024):
                        progress50Expectation.fulfill()
                    default:
                        XCTFail("unexpected progress")
                    }
                },
                completion: { result in
                    switch result {
                    case .success:
                        XCTFail("unexpected success")
                    case .failure(let error):
                        #if os(macOS)
                        // FIXME: URLSession losses the full error description when going
                        // from Swift.Error to NSError which is then received in
                        // urlSession(_ session: URLSession, task downloadTask: URLSessionTask, didCompleteWithError error: Error?)
                        XCTAssertNotNil(error as? HTTPClientError)
                        #else
                        XCTAssertEqual(error as? HTTPClientError, HTTPClientError.downloadError(clientError.description))
                        #endif
                    }
                    completionExpectation.fulfill()
                }
            )

            MockURLProtocol.onRequest(request) { request in
                MockURLProtocol.sendResponse(statusCode: 200, headers: ["Content-Length": "1024"], for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendData(Data(count: 512), for: request)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockURLProtocol.sendError(clientError, for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }

    func testDownloadServerError() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let completionExpectation = XCTestExpectation(description: "completion")

            let url = URL(string: "https://downloader-tests.com/testServerError.zip")!
            var request = HTTPClient.Request.download(url: url, fileSystem: localFileSystem, destination: tmpdir.appending(component: "download"))
            request.options.validResponseCodes = [200]
            httpClient.execute(
                request,
                progress: { _, _ in
                    XCTFail("unexpected progress")
                },
                completion: { result in
                    switch result {
                    case .success:
                        XCTFail("unexpected success")
                    case .failure(let error):
                        XCTAssertEqual(error as? HTTPClientError, HTTPClientError.badResponseStatusCode(500))
                    }
                    completionExpectation.fulfill()
                }
            )

            MockURLProtocol.onRequest(request) { request in
                MockURLProtocol.sendResponse(statusCode: 500, for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendCompletion(for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }

    func testDownloadFileSystemError() throws {
        #if !os(macOS)
        // URLSession Download tests can only run on macOS
        // as re-libs-foundation's URLSessionTask implementation which expects the temporaryFileURL property to be on the request.
        // and there is no way to set it in a mock
        // https://github.com/apple/swift-corelibs-foundation/pull/2593 tries to address the latter part
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSessionHTTPClient(configuration: configuration)
        let httpClient = HTTPClient(handler: urlSession.execute)

        try testWithTemporaryDirectory { tmpdir in
            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let completionExpectation = XCTestExpectation(description: "error")

            let url = URL(string: "https://downloader-tests.com/testFileSystemError.zip")!
            let request = HTTPClient.Request.download(url: url, fileSystem: FailingFileSystem(), destination: tmpdir.appending(component: "download"))
            httpClient.execute(request, progress: { _, _ in }, completion: { result in
                switch result {
                case .success:
                    XCTFail("unexpected success")
                case .failure(let error):
                    XCTAssertEqual(error as? FileSystemError, FileSystemError(.unsupported))
                }
                completionExpectation.fulfill()
            })

            MockURLProtocol.onRequest(request) { request in
                MockURLProtocol.sendResponse(statusCode: 200, for: request)
                didStartLoadingExpectation.fulfill()
            }
            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            MockURLProtocol.sendData(Data([0xDE, 0xAD, 0xBE, 0xEF]), for: request)
            MockURLProtocol.sendCompletion(for: request)
            wait(for: [completionExpectation], timeout: 1.0)
        }
    }
}

private class MockURLProtocol: URLProtocol {
    typealias Action = (URLRequest) -> Void

    private static var observers = ThreadSafeKeyValueStore<Key, Action>()
    private static var requests = ThreadSafeKeyValueStore<Key, URLProtocol>()

    static func onRequest(_ request: HTTPClientRequest, completion: @escaping Action) {
        self.onRequest(request.methodString(), request.url, completion: completion)
    }

    static func onRequest(_ method: String, _ url: URL, completion: @escaping Action) {
        let key = Key(method, url)
        guard !self.observers.contains(key) else {
            return XCTFail("does not support multiple observers for the same url")
        }
        self.observers[key] = completion
    }

    static func respond(_ request: HTTPClientRequest, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil) {
        self.respond(request.methodString(), request.url, statusCode: statusCode, headers: headers, body: body)
    }

    static func respond(_ request: URLRequest, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil) {
        self.respond(request.httpMethod!, request.url!, statusCode: statusCode, headers: headers, body: body)
    }

    static func respond(_ method: String, _ url: URL, statusCode: Int, headers: [String: String]? = nil, body: Data? = nil) {
        let key = Key(method, url)
        self.sendResponse(statusCode: statusCode, headers: headers, for: key)
        if let data = body {
            self.sendData(data, for: key)
        }
        self.sendCompletion(for: key)
    }

    static func sendResponse(statusCode: Int, headers: [String: String]? = nil, for request: URLRequest) {
        self.sendResponse(request.httpMethod!, request.url!, statusCode: statusCode, headers: headers)
    }

    static func sendResponse(statusCode: Int, headers: [String: String]? = nil, for request: HTTPClientRequest) {
        self.sendResponse(request.methodString(), request.url, statusCode: statusCode, headers: headers)
    }

    static func sendResponse(_ method: String, _ url: URL, statusCode: Int, headers: [String: String]? = nil) {
        let key = Key(method, url)
        self.sendResponse(statusCode: statusCode, headers: headers, for: key)
    }

    static func sendData(_ data: Data, for request: HTTPClientRequest) {
        self.sendData(request.methodString(), request.url, data)
    }

    static func sendData(_ method: String, _ url: URL, _ data: Data) {
        let key = Key(method, url)
        self.sendData(data, for: key)
    }

    static func sendCompletion(for request: HTTPClientRequest) {
        self.sendCompletion(request.methodString(), request.url)
    }

    static func sendCompletion(_ method: String, _ url: URL) {
        let key = Key(method, url)
        self.sendCompletion(for: key)
    }

    static func sendError(_ error: Error, for request: HTTPClientRequest) {
        self.sendError(request.methodString(), request.url, error)
    }

    static func sendError(_ method: String, _ url: URL, _ error: Error) {
        let key = Key(method, url)
        self.sendError(error, for: key)
    }

    private static func sendResponse(statusCode: Int, headers: [String: String]? = nil, for key: Key) {
        guard let request = self.requests[key] else {
            return XCTFail("url did not start loading")
        }
        let response = HTTPURLResponse(url: key.url, statusCode: statusCode, httpVersion: "1.1", headerFields: headers)!
        request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private static func sendData(_ data: Data, for key: Key) {
        guard let request = self.requests[key] else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocol(request, didLoad: data)
    }

    private static func sendCompletion(for key: Key) {
        guard let request = self.requests[key] else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocolDidFinishLoading(request)
    }

    private static func sendError(_ error: Error, for key: Key) {
        guard let request = self.requests[key] else {
            return XCTFail("url did not start loading")
        }
        request.client?.urlProtocol(request, didFailWithError: error)
    }

    private struct Key: Hashable {
        let method: String
        let url: URL

        init(_ method: String, _ url: URL) {
            self.method = method
            self.url = url
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
            let key = Key(method, url)
            Self.requests[key] = self

            guard let action = Self.observers[key] else {
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
            let key = Key(method, url)
            Self.requests[key] = nil
        }
    }
}

class FailingFileSystem: FileSystem {
    var currentWorkingDirectory: AbsolutePath? {
        fatalError("unexpected call")
    }

    var homeDirectory: AbsolutePath {
        fatalError("unexpected call")
    }

    var cachesDirectory: AbsolutePath? {
        fatalError("unexpected call")
    }

    var tempDirectory: AbsolutePath {
        fatalError("unexpected call")
    }

    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        fatalError("unexpected call")
    }

    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        fatalError("unexpected call")
    }

    func isDirectory(_: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isFile(_: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isExecutableFile(_: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isSymlink(_: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isReadable(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isWritable(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func getDirectoryContents(_: AbsolutePath) throws -> [String] {
        fatalError("unexpected call")
    }

    func readFileContents(_: AbsolutePath) throws -> ByteString {
        fatalError("unexpected call")
    }

    func removeFileTree(_: AbsolutePath) throws {
        fatalError("unexpected call")
    }

    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        fatalError("unexpected call")
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        fatalError("unexpected call")
    }

    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        fatalError("unexpected call")
    }

    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        fatalError("unexpected call")
    }

    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        fatalError("unexpected call")
    }

    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        throw FileSystemError(.unsupported)
    }
}

fileprivate struct NetrcAuthorizationWrapper: AuthorizationProvider {
    let underlying: Netrc

    func authentication(for url: URL) -> (user: String, password: String)? {
        self.underlying.authorization(for: url).map{ (user: $0.login, password: $0.password) }
    }
}
