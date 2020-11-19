/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

import Basics
@testable import PackageCollections
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import TSCUtility

class JSONPackageCollectionProviderTests: XCTestCase {
    func testGood() throws {
        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "JSON", "good.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data = Data(try localFileSystem.readFileContents(path).contents)

            let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = JSONPackageCollectionProvider(httpClient: httpClient)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.description, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.repository, .init(url: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.description, "Package One")
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.packageName, "PackageOne")
            XCTAssertEqual(version.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(version.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(version.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(version.verifiedSwiftVersions, [SwiftLanguageVersion(string: "5.1")!])
            XCTAssertEqual(version.verifiedPlatforms, [.macOS, .iOS, .linux])
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
        }
    }

    func testLocalFile() throws {
        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "JSON", "good.json")
            let data = Data(try localFileSystem.readFileContents(path).contents)

            let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
                XCTAssertEqual(request.url, path.asURL, "url should match")
                switch request.method {
                case .head:
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = JSONPackageCollectionProvider(httpClient: httpClient)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: path.asURL)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.description, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.repository, .init(url: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.description, "Package One")
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.packageName, "PackageOne")
            XCTAssertEqual(version.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(version.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(version.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(version.verifiedSwiftVersions, [SwiftLanguageVersion(string: "5.1")!])
            XCTAssertEqual(version.verifiedPlatforms, [.macOS, .iOS, .linux])
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
        }
    }

    func testInvalidURL() throws {
        let url = URL(string: "ftp://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        var httpClient = HTTPClient(handler: { (_, _) -> Void in fatalError("should not be called") })
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            guard let internalError = (error as? MultipleErrors)?.errors.first else {
                return XCTFail("invalid error \(error)")
            }
            XCTAssertEqual(internalError as? ValidationError, ValidationError.other(description: "Schema not allowed: \(url.absoluteString)"))
        })
    }

    func testExceedsDownloadSizeLimitHead() throws {
        let maxSize = 50
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            callback(.success(.init(statusCode: 200,
                                    headers: .init([.init(name: "Content-Length", value: "\(maxSize * 2)")]))))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let configuration = JSONPackageCollectionProvider.Configuration(maximumSizeInBytes: 10)
        let provider = JSONPackageCollectionProvider(configuration: configuration, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            switch error {
            case JSONPackageCollectionProvider.Errors.responseTooLarge(let size):
                XCTAssertEqual(size, maxSize * 2)
            default:
                XCTFail("unexpected error \(error)")
            }
        })
    }

    func testExceedsDownloadSizeLimitGet() throws {
        let maxSize = 50
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                callback(.success(.init(statusCode: 200,
                                        headers: .init([.init(name: "Content-Length", value: "0")]))))
            case .get:
                callback(.success(.init(statusCode: 200,
                                        headers: .init([.init(name: "Content-Length", value: "\(maxSize * 2)")]))))
            default:
                XCTFail("method should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let configuration = JSONPackageCollectionProvider.Configuration(maximumSizeInBytes: 10)
        let provider = JSONPackageCollectionProvider(configuration: configuration, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            switch error {
            case JSONPackageCollectionProvider.Errors.responseTooLarge(let size):
                XCTAssertEqual(size, maxSize * 2)
            default:
                XCTFail("unexpected error \(error)")
            }
        })
    }

    func testNoContentLengthOnGet() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertTrue([.head, .get].contains(request.method), "method should match")
            callback(.success(.init(statusCode: 200)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let configuration = JSONPackageCollectionProvider.Configuration(maximumSizeInBytes: 10)
        let provider = JSONPackageCollectionProvider(configuration: configuration, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            switch error {
            case JSONPackageCollectionProvider.Errors.invalidResponse(let error):
                XCTAssertEqual(error, "Missing Content-Length header")
            default:
                XCTFail("unexpected error \(error)")
            }
        })
    }

    func testUnsuccessfulHead() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        let statusCode = Int.random(in: 201 ... 550)

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            callback(.success(.init(statusCode: statusCode)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? HTTPClientError, .badResponseStatusCode(statusCode))
        })
    }

    func testUnsuccessfulGet() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        let statusCode = Int.random(in: 201 ... 550)

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                callback(.success(.init(statusCode: 200)))
            case .get:
                callback(.success(.init(statusCode: statusCode)))
            default:
                XCTFail("method should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? HTTPClientError, .badResponseStatusCode(statusCode))
        })
    }

    func testBadJSON() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let data = "blah".data(using: .utf8)!

        let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                callback(.success(.init(statusCode: 200)))
            case .get:
                callback(.success(.init(statusCode: 200,
                                        headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                        body: data)))
            default:
                XCTFail("method should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            switch error {
            case JSONPackageCollectionProvider.Errors.invalidJSON:
                break
            default:
                XCTFail("unexpected error \(error)")
            }
        })
    }
}
