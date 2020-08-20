/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCUtility
import TSCTestSupport
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class DownloaderTests: XCTestCase {

    func testSuccess() {
      // FIXME: Remove once https://github.com/apple/swift-corelibs-foundation/pull/2593 gets inside a toolchain.
      #if os(macOS)
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration)

        mktmpdir { tmpdir in
            let url = URL(string: "https://downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")

            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let successExpectation = XCTestExpectation(description: "success")
            MockURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

            downloader.downloadFile(at: url, to: destination, progress: { bytesDownloaded, totalBytesToDownload in
                switch (bytesDownloaded, totalBytesToDownload) {
                case (512, 1024):
                    progress50Expectation.fulfill()
                case (1024, 1024):
                    progress100Expectation.fulfill()
                default:
                    XCTFail("unexpected progress")
                }
            }, completion: { result in
                switch result {
                case .success:
                    XCTAssert(localFileSystem.exists(destination))
                    let bytes = ByteString(Array(repeating: 0xbe, count: 512) + Array(repeating: 0xef, count: 512))
                    XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    successExpectation.fulfill()
                case .failure(let error):
                    XCTFail("\(error)")
                }
            })

            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: [
                "Content-Length": "1024"
            ])!

            MockURLProtocol.sendResponse(response, for: url)
            MockURLProtocol.sendData(Data(repeating: 0xbe, count: 512), for: url)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockURLProtocol.sendData(Data(repeating: 0xef, count: 512), for: url)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockURLProtocol.sendCompletion(for: url)
            wait(for: [successExpectation], timeout: 1.0)
        }
      #endif
    }
    
    #if os(macOS)
    @available(OSX 10.13, *)
    /// Netrc feature depends upon `NSTextCheckingResult.range(withName name: String) -> NSRange`,
    /// which is only available in macOS 10.13+ at this time.
    func testAuthenticatedSuccess() {
        let netrcContent = "machine protected.downloader-tests.com login anonymous password qwerty"
        guard case .success(let netrc) = Netrc.from(netrcContent) else {
            return XCTFail("Cannot load netrc content")
        }
        let authData = "anonymous:qwerty".data(using: .utf8)!
        let testAuthHeader = "Basic \(authData.base64EncodedString())"
        
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockAuthenticatingURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration)

        mktmpdir { tmpdir in
            let url = URL(string: "https://protected.downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")

            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let successExpectation = XCTestExpectation(description: "success")
            MockAuthenticatingURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

            downloader.downloadFile(at: url, to: destination, withAuthorizationProvider: netrc, progress: { bytesDownloaded, totalBytesToDownload in
                
                XCTAssertEqual(MockAuthenticatingURLProtocol.authenticationHeader(for: url), testAuthHeader)

                switch (bytesDownloaded, totalBytesToDownload) {
                case (512, 1024):
                    progress50Expectation.fulfill()
                case (1024, 1024):
                    progress100Expectation.fulfill()
                default:
                    XCTFail("unexpected progress")
                }
            }, completion: { result in
                switch result {
                case .success:
                    XCTAssert(localFileSystem.exists(destination))
                    let bytes = ByteString(Array(repeating: 0xbe, count: 512) + Array(repeating: 0xef, count: 512))
                    XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    successExpectation.fulfill()
                case .failure(let error):
                    XCTFail("\(error)")
                }
            })

            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: [
                "Content-Length": "1024"
            ])!

            MockAuthenticatingURLProtocol.sendResponse(response, for: url)
            MockAuthenticatingURLProtocol.sendData(Data(repeating: 0xbe, count: 512), for: url)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockAuthenticatingURLProtocol.sendData(Data(repeating: 0xef, count: 512), for: url)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockAuthenticatingURLProtocol.sendCompletion(for: url)
            wait(for: [successExpectation], timeout: 1.0)
        }
    }
    #endif
    
    #if os(macOS)
    @available(OSX 10.13, *)
    /// Netrc feature depends upon `NSTextCheckingResult.range(withName name: String) -> NSRange`,
    /// which is only available in macOS 10.13+ at this time.
    func testDefaultAuthenticationSuccess() {
        let netrcContent = "default login default password default"
        guard case .success(let netrc) = Netrc.from(netrcContent) else {
            return XCTFail("Cannot load netrc content")
        }
        let authData = "default:default".data(using: .utf8)!
        let testAuthHeader = "Basic \(authData.base64EncodedString())"
        
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockAuthenticatingURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration)

        mktmpdir { tmpdir in
            let url = URL(string: "https://restricted.downloader-tests.com/testBasics.zip")!
            let destination = tmpdir.appending(component: "download")

            let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
            let progress50Expectation = XCTestExpectation(description: "progress50")
            let progress100Expectation = XCTestExpectation(description: "progress100")
            let successExpectation = XCTestExpectation(description: "success")
            MockAuthenticatingURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

            downloader.downloadFile(at: url, to: destination, withAuthorizationProvider: netrc, progress: { bytesDownloaded, totalBytesToDownload in
                
                XCTAssertEqual(MockAuthenticatingURLProtocol.authenticationHeader(for: url), testAuthHeader)

                switch (bytesDownloaded, totalBytesToDownload) {
                case (512, 1024):
                    progress50Expectation.fulfill()
                case (1024, 1024):
                    progress100Expectation.fulfill()
                default:
                    XCTFail("unexpected progress")
                }
            }, completion: { result in
                switch result {
                case .success:
                    XCTAssert(localFileSystem.exists(destination))
                    let bytes = ByteString(Array(repeating: 0xbe, count: 512) + Array(repeating: 0xef, count: 512))
                    XCTAssertEqual(try! localFileSystem.readFileContents(destination), bytes)
                    successExpectation.fulfill()
                case .failure(let error):
                    XCTFail("\(error)")
                }
            })

            wait(for: [didStartLoadingExpectation], timeout: 1.0)

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: [
                "Content-Length": "1024"
            ])!

            MockAuthenticatingURLProtocol.sendResponse(response, for: url)
            MockAuthenticatingURLProtocol.sendData(Data(repeating: 0xbe, count: 512), for: url)
            wait(for: [progress50Expectation], timeout: 1.0)
            MockAuthenticatingURLProtocol.sendData(Data(repeating: 0xef, count: 512), for: url)
            wait(for: [progress100Expectation], timeout: 1.0)
            MockAuthenticatingURLProtocol.sendCompletion(for: url)
            wait(for: [successExpectation], timeout: 1.0)
        }
    }
    #endif

    func testClientError() {
      // FIXME: Remove once https://github.com/apple/swift-corelibs-foundation/pull/2593 gets inside a toolchain.
      #if os(macOS)
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration)
        let url = URL(string: "https://downloader-tests.com/testClientError.zip")!

        let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
        let progress50Expectation = XCTestExpectation(description: "progress50")
        let errorExpectation = XCTestExpectation(description: "error")
        MockURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

        downloader.downloadFile(at: url, to: AbsolutePath("/"), progress: { bytesDownloaded, totalBytesToDownload in
            switch (bytesDownloaded, totalBytesToDownload) {
            case (512, 1024):
                progress50Expectation.fulfill()
            default:
                XCTFail("unexpected progress")
            }
        }, completion: { result in
            switch result {
            case .success:
                XCTFail("unexpected success")
            case .failure(let error):
                guard case .clientError(let underlyingError) = error else {
                    XCTFail("wrong error: \(error)")
                    return
                }

                // Errors on Linux don't encode the Swift type in the domain.
              #if os(macOS)
                XCTAssertMatch((underlyingError as NSError).domain, .contains("DummyError"))
              #endif
                errorExpectation.fulfill()
            }
        })

        wait(for: [didStartLoadingExpectation], timeout: 1.0)

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: [
            "Content-Length": "1024"
        ])!

        MockURLProtocol.sendResponse(response, for: url)
        MockURLProtocol.sendData(Data(count: 512), for: url)
        wait(for: [progress50Expectation], timeout: 1.0)
        MockURLProtocol.sendError(DummyError(), for: url)
        wait(for: [errorExpectation], timeout: 1.0)
      #endif
    }

    func testServerError() {
      // FIXME: Remove once https://github.com/apple/swift-corelibs-foundation/pull/2593 gets inside a toolchain.
      #if os(macOS)
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration)
        let url = URL(string: "https://downloader-tests.com/testServerError.zip")!

        let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
        let errorExpectation = XCTestExpectation(description: "error")
        MockURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

        downloader.downloadFile(at: url, to: AbsolutePath("/"), progress: { _, _ in
            XCTFail("unexpected progress")
        }, completion: { result in
            switch result {
            case .success:
                XCTFail("unexpected success")
            case .failure(let error):
                guard case .serverError(let statusCode) = error else {
                    XCTFail("wrong error: \(error)")
                    return
                }

                XCTAssertEqual(statusCode, 418)
                errorExpectation.fulfill()
            }
        })

        wait(for: [didStartLoadingExpectation], timeout: 1.0)

        let response = HTTPURLResponse(url: url, statusCode: 418, httpVersion: "1.1", headerFields: [:])!

        MockURLProtocol.sendResponse(response, for: url)
        MockURLProtocol.sendCompletion(for: url)
        wait(for: [errorExpectation], timeout: 1.0)
      #endif
    }

    func testFileSystemError() {
      // FIXME: Remove once https://github.com/apple/swift-corelibs-foundation/pull/2593 gets inside a toolchain.
      #if os(macOS)
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [MockURLProtocol.self]
        let downloader = FoundationDownloader(configuration: configuration, fileSystem: FailingFileSystem())
        let url = URL(string: "https://downloader-tests.com/testFileSystemError.zip")!

        let didStartLoadingExpectation = XCTestExpectation(description: "didStartLoading")
        let errorExpectation = XCTestExpectation(description: "error")
        MockURLProtocol.notifyDidStartLoading(for: url, completion: { didStartLoadingExpectation.fulfill() })

        downloader.downloadFile(at: url, to: AbsolutePath("/"), progress: { _, _ in }, completion: { result in
            switch result {
            case .success:
                XCTFail("unexpected success")
            case .failure(let error):
                guard case .fileSystemError(let fileSystemError) = error else {
                    XCTFail("wrong error: \(error)")
                    return
                }

                XCTAssert(fileSystemError is DummyError)
                errorExpectation.fulfill()
            }
        })

        wait(for: [didStartLoadingExpectation], timeout: 1.0)

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: [:])!

        MockURLProtocol.sendResponse(response, for: url)
        MockURLProtocol.sendData(Data([0xde, 0xad, 0xbe, 0xef]), for: url)
        MockURLProtocol.sendCompletion(for: url)
        wait(for: [errorExpectation], timeout: 1.0)
      #endif
    }
}

private struct DummyError: Error {
}

private typealias Action = () -> Void

private class MockAuthenticatingURLProtocol: MockURLProtocol {
    
    fileprivate static func authenticationHeader(for url: Foundation.URL) -> String? {
        guard let instance = instance(for: url) else {
            fatalError("url did not start loading")
        }
        return instance.request.allHTTPHeaderFields?["Authorization"]
    }
}

private class MockURLProtocol: URLProtocol {
    private static var queue = DispatchQueue(label: "org.swift.swiftpm.basic-tests.mock-url-protocol")
    private static var observers: [Foundation.URL: Action] = [:]
    private static var instances: [Foundation.URL: URLProtocol] = [:]

    static func notifyDidStartLoading(
        for url: Foundation.URL,
        completion: @escaping Action,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        queue.async {
            guard !observers.keys.contains(url) else {
                fatalError("does not support multiple observers for the same url", file: file, line: line)
            }

            observers[url] = completion
        }
    }

    static func sendResponse(
        _ response: URLResponse,
        for url: Foundation.URL,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        queue.async {
            guard let instance = instances[url] else {
                fatalError("url did not start loading", file: file, line: line)
            }

            instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
    }

    static func sendData(_ data: Data, for url: Foundation.URL, file: StaticString = #file, line: UInt = #line) {
        queue.async {
            guard let instance = instances[url] else {
                fatalError("url did not start loading", file: file, line: line)
            }

            instance.client?.urlProtocol(instance, didLoad: data)
        }
    }

    static func sendCompletion(for url: Foundation.URL, file: StaticString = #file, line: UInt = #line) {
        queue.async {
            guard let instance = instances[url] else {
                fatalError("url did not start loading", file: file, line: line)
            }

            instance.client?.urlProtocolDidFinishLoading(instance)
        }
    }

    static func sendError(_ error: Error, for url: Foundation.URL, file: StaticString = #file, line: UInt = #line) {
        queue.async {
            guard let instance = instances[url] else {
                fatalError("url did not start loading", file: file, line: line)
            }

            instance.client?.urlProtocol(instance, didFailWithError: error)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      #if !os(macOS)
        // This is necessary to avoid a crash in core-libs-foundation's URLSessionTask implementation which expects the
        // temporaryFileURL property to be set.
        let mutableRequest = ((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest)!
        let tempPath = try! withTemporaryDirectory(prefix: "mock-url-protocol") { $0 }
        MockURLProtocol.setProperty(tempPath.asURL, forKey: "temporaryFileURL", in: mutableRequest)
        return (mutableRequest as URLRequest)
      #else
        return request
      #endif
    }

    override func startLoading() {
        Self.queue.async {
            let url = self.request.url!
            Self.instances[url] = self
            Self.observers[url]?()
        }
    }

    override func stopLoading() {
        Self.queue.async {
          #if !os(macOS)
            let tempPath = MockURLProtocol.property(forKey: "temporaryFileURL", in: self.request) as! NSURL
            try! localFileSystem.removeFileTree(AbsolutePath(tempPath.path!))
          #endif

            let url = self.request.url!
            Self.instances[url] = nil
        }
    }
    
    fileprivate static func instance(for url: Foundation.URL) -> URLProtocol? {
        return Self.instances[url]
    }
}

class FailingFileSystem: FileSystem {
    var currentWorkingDirectory: AbsolutePath? {
        fatalError("unexpected call")
    }

    var homeDirectory: AbsolutePath {
        fatalError("unexpected call")
    }

    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        fatalError("unexpected call")
    }

    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        fatalError("unexpected call")
    }

    func isDirectory(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isFile(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isExecutableFile(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func isSymlink(_ path: AbsolutePath) -> Bool {
        fatalError("unexpected call")
    }

    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        fatalError("unexpected call")
    }

    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        fatalError("unexpected call")
    }

    func removeFileTree(_ path: AbsolutePath) throws {
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

    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        fatalError("unexpected call")
    }

    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        throw DummyError()
    }
}
