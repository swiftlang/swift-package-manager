//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
@testable import PackageCollections
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class PackageIndexTests: XCTestCase {
    func testGetPackageMetadata() throws {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = true
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let packageIdentity = PackageIdentity(url: repoURL)
        let package = makeMockPackage(id: "test-package")
        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, url.appendingPathComponent("packages").appendingPathComponent(packageIdentity.description)):
                let data = try! JSONEncoder.makeWithDefaults().encode(package)
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }
        
        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
                
        let index = PackageIndex(configuration: configuration, customHTTPClient: httpClient, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let metadata = try tsc_await { callback in index.getPackageMetadata(identity: .init(url: repoURL), location: repoURL.absoluteString, callback: callback) }
        XCTAssertEqual(metadata.package.identity, package.identity)
        XCTAssert(metadata.collections.isEmpty)
        XCTAssertNotNil(metadata.provider)
    }
    
    func testGetPackageMetadata_featureDisabled() {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = false
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        XCTAssertThrowsError(try tsc_await { callback in index.getPackageMetadata(identity: .init(url: repoURL), location: repoURL.absoluteString, callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .featureDisabled)
        }
    }
    
    func testGetPackageMetadata_notConfigured() {
        var configuration = PackageIndexConfiguration(url: nil, disableCache: true)
        configuration.enabled = true
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        XCTAssertThrowsError(try tsc_await { callback in index.getPackageMetadata(identity: .init(url: repoURL), location: repoURL.absoluteString, callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .notConfigured)
        }
    }
    
    func testFindPackages() throws {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, searchResultMaxItemsCount: 10, disableCache: true)
        configuration.enabled = true
        
        let packages = (0..<3).map { packageIndex -> PackageCollectionsModel.Package in
            makeMockPackage(id: "package-\(packageIndex)")
        }
        let query = "foobar"
        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, URL(string: url.appendingPathComponent("search").absoluteString + "?q=\(query)")!):
                let data = try! JSONEncoder.makeWithDefaults().encode(packages)
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }
        
        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
                
        let index = PackageIndex(configuration: configuration, customHTTPClient: httpClient, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let result = try tsc_await { callback in index.findPackages(query, callback: callback) }
        XCTAssertEqual(result.items.count, packages.count)
        for (i, item) in result.items.enumerated() {
            XCTAssertEqual(item.package.identity, packages[i].identity)
            XCTAssert(item.collections.isEmpty)
            XCTAssertEqual(item.indexes, [url])
        }
    }
    
    func testFindPackages_resultsLimit() throws {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, searchResultMaxItemsCount: 3, disableCache: true)
        configuration.enabled = true
        
        // This is larger than searchResultMaxItemsCount
        let packages = (0..<5).map { packageIndex -> PackageCollectionsModel.Package in
            makeMockPackage(id: "package-\(packageIndex)")
        }
        let query = "foobar"
        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, URL(string: url.appendingPathComponent("search").absoluteString + "?q=\(query)")!):
                let data = try! JSONEncoder.makeWithDefaults().encode(packages)
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }
        
        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
                
        let index = PackageIndex(configuration: configuration, customHTTPClient: httpClient, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let result = try tsc_await { callback in index.findPackages(query, callback: callback) }
        XCTAssertEqual(result.items.count, configuration.searchResultMaxItemsCount)
        for (i, item) in result.items.enumerated() {
            XCTAssertEqual(item.package.identity, packages[i].identity)
            XCTAssert(item.collections.isEmpty)
            XCTAssertEqual(item.indexes, [url])
        }
    }
    
    func testFindPackages_featureDisabled() {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = false
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        XCTAssertThrowsError(try tsc_await { callback in index.findPackages("foobar", callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .featureDisabled)
        }
    }
    
    func testFindPackages_notConfigured() {
        var configuration = PackageIndexConfiguration(url: nil, disableCache: true)
        configuration.enabled = true
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        XCTAssertThrowsError(try tsc_await { callback in index.findPackages("foobar", callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .notConfigured)
        }
    }
    
    func testListPackages() throws {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = true
        
        let offset = 4
        let limit = 3
        let total = 20
        let packages = (0..<limit).map { packageIndex -> PackageCollectionsModel.Package in
            makeMockPackage(id: "package-\(packageIndex)")
        }
        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, URL(string: url.appendingPathComponent("packages").absoluteString + "?offset=\(offset)&limit=\(limit)")!):
                let response = PackageIndex.ListResponse(items: packages, total: total)
                let data = try! JSONEncoder.makeWithDefaults().encode(response)
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }
        
        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
                
        let index = PackageIndex(configuration: configuration, customHTTPClient: httpClient, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let result = try tsc_await { callback in index.listPackages(offset: offset, limit: limit, callback: callback) }
        XCTAssertEqual(result.items.count, packages.count)
        XCTAssertEqual(result.offset, offset)
        XCTAssertEqual(result.limit, limit)
        XCTAssertEqual(result.total, total)
    }
    
    func testListPackages_featureDisabled() {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = false
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        XCTAssertThrowsError(try tsc_await { callback in index.listPackages(offset: 0, limit: 10, callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .featureDisabled)
        }
    }
    
    func testListPackages_notConfigured() {
        var configuration = PackageIndexConfiguration(url: nil, disableCache: true)
        configuration.enabled = true
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        XCTAssertThrowsError(try tsc_await { callback in index.listPackages(offset: 0, limit: 10, callback: callback) }) { error in
            XCTAssertEqual(error as? PackageIndexError, .notConfigured)
        }
    }
    
    func testAsPackageMetadataProvider() throws {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = true
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        let packageIdentity = PackageIdentity(url: repoURL)
        let package = makeMockPackage(id: "test-package")
        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, url.appendingPathComponent("packages").appendingPathComponent(packageIdentity.description)):
                let data = try! JSONEncoder.makeWithDefaults().encode(package)
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                          body: data)))
            default:
                XCTFail("method and url should match")
            }
        }
        
        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
                
        let index = PackageIndex(configuration: configuration, customHTTPClient: httpClient, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let metadata = try index.syncGet(identity: .init(url: repoURL), location: repoURL.absoluteString)
        XCTAssertEqual(metadata.summary, package.summary)
    }
    
    func testAsGetPackageMetadataProvider_featureDisabled() {
        let url = URL(string: "https://package-index.test")!
        var configuration = PackageIndexConfiguration(url: url, disableCache: true)
        configuration.enabled = false
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        XCTAssertThrowsError(try index.syncGet(identity: .init(url: repoURL), location: repoURL.absoluteString)) { error in
            XCTAssertEqual(error as? PackageIndexError, .featureDisabled)
        }
    }
    
    func testAsGetPackageMetadataProvider_notConfigured() {
        var configuration = PackageIndexConfiguration(url: nil, disableCache: true)
        configuration.enabled = true
                
        let index = PackageIndex(configuration: configuration, callbackQueue: .sharedConcurrent, observabilityScope: ObservabilitySystem.NOOP)
        defer { XCTAssertNoThrow(try index.close()) }
        
        let repoURL = URL(string: "https://github.com/octocat/Hello-World.git")!
        XCTAssertThrowsError(try index.syncGet(identity: .init(url: repoURL), location: repoURL.absoluteString)) { error in
            XCTAssertEqual(error as? PackageIndexError, .notConfigured)
        }
    }
}

private extension PackageIndex {
    func syncGet(identity: PackageIdentity, location: String) throws -> Model.PackageBasicMetadata {
        try tsc_await { callback in
            self.get(identity: identity, location: location) { result, _ in callback(result) }
        }
    }
}
