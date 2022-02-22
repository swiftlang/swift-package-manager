/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

import Basics
@testable import PackageCollections
import PackageCollectionsSigning
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic

class JSONPackageCollectionProviderTests: XCTestCase {
    func testGood() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
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
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)

            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.summary, "Fixed a few bugs")
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertNotNil(version.createdAt)
            XCTAssertFalse(collection.isSigned)

            // "1.8.3" is originally "v1.8.3"
            XCTAssertEqual(["2.1.0", "1.8.3"], collection.packages[1].versions.map { $0.version.description })
        }
    }

    func testLocalFile() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good.json")

            var httpClient = HTTPClient(handler: { (_, _, _) -> Void in fatalError("should not be called") })
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = JSONPackageCollectionProvider(httpClient: httpClient)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: path.asURL)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)

            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertFalse(collection.isSigned)

            // "1.8.3" is originally "v1.8.3"
            XCTAssertEqual(["2.1.0", "1.8.3"], collection.packages[1].versions.map { $0.version.description })
        }
    }

    func testInvalidURL() throws {
        let url = URL(string: "ftp://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        var httpClient = HTTPClient(handler: { (_, _, _) -> Void in fatalError("should not be called") })
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            guard case .invalidSource(let errorMessage) = error as? JSONPackageCollectionProviderError else {
                return XCTFail("invalid error \(error)")
            }
            XCTAssertTrue(errorMessage.contains("Scheme (\"ftp\") not allowed: \(url.absoluteString)"))
        })
    }

    func testExceedsDownloadSizeLimitHead() throws {
        let maxSize: Int64 = 50
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            completion(.success(.init(statusCode: 200,
                                      headers: .init([.init(name: "Content-Length", value: "\(maxSize * 2)")]))))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let configuration = JSONPackageCollectionProvider.Configuration(maximumSizeInBytes: 10)
        let provider = JSONPackageCollectionProvider(configuration: configuration, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .responseTooLarge(url, maxSize * 2))
        })
    }

    func testExceedsDownloadSizeLimitGet() throws {
        let maxSize: Int64 = 50
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "0")]))))
            case .get:
                completion(.success(.init(statusCode: 200,
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
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .responseTooLarge(url, maxSize * 2))
        })
    }

    func testNoContentLengthOnGet() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertTrue([.head, .get].contains(request.method), "method should match")
            completion(.success(.init(statusCode: 200)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let configuration = JSONPackageCollectionProvider.Configuration(maximumSizeInBytes: 10)
        let provider = JSONPackageCollectionProvider(configuration: configuration, httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .invalidResponse(url, "Missing Content-Length header"))
        })
    }

    func testExceedsDownloadSizeLimitProgress() throws {
        let maxSize: Int64 = 50
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, progress, completion in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                completion(.success(.init(statusCode: 200,
                                          headers: .init([.init(name: "Content-Length", value: "0")]))))
            case .get:
                progress?(Int64(maxSize * 2), 0)
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
            XCTAssertEqual(error as? HTTPClientError, .responseTooLarge(maxSize * 2))
        })
    }

    func testUnsuccessfulHead_unavailable() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        let statusCode = Int.random(in: 500 ... 550) // Don't use 404 because it leads to a different error message

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            completion(.success(.init(statusCode: statusCode)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .collectionUnavailable(url, statusCode))
        })
    }

    func testUnsuccessfulGet_unavailable() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
        let statusCode = Int.random(in: 500 ... 550) // Don't use 404 because it leads to a different error message

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                completion(.success(.init(statusCode: 200, headers: .init([.init(name: "Content-Length", value: "1")]))))
            case .get:
                completion(.success(.init(statusCode: statusCode)))
            default:
                XCTFail("method should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .collectionUnavailable(url, statusCode))
        })
    }

    func testUnsuccessfulHead_notFound() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            XCTAssertEqual(request.method, .head, "method should match")
            completion(.success(.init(statusCode: 404)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .collectionNotFound(url))
        })
    }

    func testUnsuccessfulGet_notFound() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                completion(.success(.init(statusCode: 200, headers: .init([.init(name: "Content-Length", value: "1")]))))
            case .get:
                completion(.success(.init(statusCode: 404)))
            default:
                XCTFail("method should match")
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = JSONPackageCollectionProvider(httpClient: httpClient)
        XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .collectionNotFound(url))
        })
    }

    func testBadJSON() throws {
        let url = URL(string: "https://www.test.com/collection.json")!
        let data = "blah".data(using: .utf8)!

        let handler: HTTPClient.Handler = { request, _, completion in
            XCTAssertEqual(request.url, url, "url should match")
            switch request.method {
            case .head:
                completion(.success(.init(statusCode: 200, headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
            case .get:
                completion(.success(.init(statusCode: 200,
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
            XCTAssertEqual(error as? JSONPackageCollectionProviderError, .invalidJSON(url))
        })
    }

    func testSignedGood() throws {
        try skipIfSignatureCheckNotSupported()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // Mark collection as having valid signature
            let signatureValidator = MockCollectionSignatureValidator(["Sample Package Collection"])
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)

            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.summary, "Fixed a few bugs")
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertNotNil(version.createdAt)
            XCTAssertTrue(collection.isSigned)
            let signature = collection.signature!
            XCTAssertTrue(signature.isVerified)
            XCTAssertEqual("Sample Subject", signature.certificate.subject.commonName)
            XCTAssertEqual("Sample Issuer", signature.certificate.issuer.commonName)

            // "1.8.3" is originally "v1.8.3"
            XCTAssertEqual(["2.1.0", "1.8.3"], collection.packages[1].versions.map { $0.version.description })
        }
    }

    func testSigned_skipSignatureCheck() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            let signatureValidator = MockCollectionSignatureValidator()
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator)
            // Skip signature check
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url, skipSignatureCheck: true)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.summary, "Fixed a few bugs")
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertNotNil(version.createdAt)
            XCTAssertTrue(collection.isSigned)
            let signature = collection.signature!
            XCTAssertFalse(signature.isVerified)
            XCTAssertEqual("Sample Subject", signature.certificate.subject.commonName)
            XCTAssertEqual("Sample Issuer", signature.certificate.issuer.commonName)
        }
    }

    func testSigned_noTrustedRootCertsConfigured() throws {
        try skipIfSignatureCheckNotSupported()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            let signatureValidator = MockCollectionSignatureValidator(hasTrustedRootCerts: false)
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

            XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
                switch error {
                case PackageCollectionError.cannotVerifySignature:
                    break
                default:
                    XCTFail("unexpected error \(error)")
                }
            })
        }
    }

    func testSignedBad() throws {
        try skipIfSignatureCheckNotSupported()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // The validator doesn't know about the test collection so its signature would be considered invalid
            let signatureValidator = MockCollectionSignatureValidator()
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

            XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
                switch error {
                case PackageCollectionError.invalidSignature:
                    break
                default:
                    XCTFail("unexpected error \(error)")
                }
            })
        }
    }

    func testSignedLocalFile() throws {
        try skipIfSignatureCheckNotSupported()

        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")

            var httpClient = HTTPClient(handler: { (_, _, _) -> Void in fatalError("should not be called") })
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // Mark collection as having valid signature
            let signatureValidator = MockCollectionSignatureValidator(["Sample Package Collection"])

            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: path.asURL)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertTrue(collection.isSigned)
            let signature = collection.signature!
            XCTAssertTrue(signature.isVerified)
            XCTAssertEqual("Sample Subject", signature.certificate.subject.commonName)
            XCTAssertEqual("Sample Issuer", signature.certificate.issuer.commonName)
        }
    }

    func testRequiredSigningGood() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // Mark collection as having valid signature
            let signatureValidator = MockCollectionSignatureValidator(["Sample Package Collection"])
            // Collections from www.test.com must be signed
            let sourceCertPolicy = PackageCollectionSourceCertificatePolicy(
                sourceCertPolicies: ["www.test.com": [.init(certPolicyKey: CertificatePolicyKey.default, base64EncodedRootCerts: nil)]]
            )
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator,
                                                         sourceCertPolicy: sourceCertPolicy)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.summary, "Fixed a few bugs")
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertNotNil(version.createdAt)
            XCTAssertTrue(collection.isSigned)
            let signature = collection.signature!
            XCTAssertTrue(signature.isVerified)
            XCTAssertEqual("Sample Subject", signature.certificate.subject.commonName)
            XCTAssertEqual("Sample Issuer", signature.certificate.issuer.commonName)
        }
    }

    func testRequiredSigningMultiplePoliciesGood() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good_signed.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // Mark collection as having valid signature
            let signatureValidator = MockCollectionSignatureValidator(certPolicyKeys: [CertificatePolicyKey.default(subjectUserID: "test")])
            // Collections from www.test.com must be signed
            let sourceCertPolicy = PackageCollectionSourceCertificatePolicy(
                sourceCertPolicies: [
                    "www.test.com": [
                        .init(certPolicyKey: CertificatePolicyKey.default, base64EncodedRootCerts: nil),
                        .init(certPolicyKey: CertificatePolicyKey.default(subjectUserID: "test"), base64EncodedRootCerts: nil),
                    ],
                ]
            )
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator,
                                                         sourceCertPolicy: sourceCertPolicy)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)
            let collection = try tsc_await { callback in provider.get(source, callback: callback) }

            XCTAssertEqual(collection.name, "Sample Package Collection")
            XCTAssertEqual(collection.overview, "This is a sample package collection listing made-up packages.")
            XCTAssertEqual(collection.keywords, ["sample package collection"])
            XCTAssertEqual(collection.createdBy?.name, "Jane Doe")
            XCTAssertEqual(collection.packages.count, 2)
            let package = collection.packages.first!
            XCTAssertEqual(package.identity, .init(urlString: "https://www.example.com/repos/RepoOne.git"))
            XCTAssertEqual(package.location, "https://www.example.com/repos/RepoOne.git")
            XCTAssertEqual(package.summary, "Package One")
            XCTAssertEqual(package.keywords, ["sample package"])
            XCTAssertEqual(package.readmeURL, URL(string: "https://www.example.com/repos/RepoOne/README")!)
            XCTAssertEqual(package.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertEqual(package.versions.count, 1)
            let version = package.versions.first!
            XCTAssertEqual(version.summary, "Fixed a few bugs")
            let manifest = version.manifests.values.first!
            XCTAssertEqual(manifest.packageName, "PackageOne")
            XCTAssertEqual(manifest.targets, [.init(name: "Foo", moduleName: "Foo")])
            XCTAssertEqual(manifest.products, [.init(name: "Foo", type: .library(.automatic), targets: [.init(name: "Foo", moduleName: "Foo")])])
            XCTAssertEqual(manifest.toolsVersion, ToolsVersion(string: "5.1")!)
            XCTAssertEqual(manifest.minimumPlatformVersions, [SupportedPlatform(platform: .macOS, version: .init("10.15"))])
            XCTAssertEqual(version.verifiedCompatibility?.count, 3)
            XCTAssertEqual(version.verifiedCompatibility!.first!.platform, .macOS)
            XCTAssertEqual(version.verifiedCompatibility!.first!.swiftVersion, SwiftLanguageVersion(string: "5.1")!)
            XCTAssertEqual(version.license, .init(type: .Apache2_0, url: URL(string: "https://www.example.com/repos/RepoOne/LICENSE")!))
            XCTAssertNotNil(version.createdAt)
            XCTAssertTrue(collection.isSigned)
            let signature = collection.signature!
            XCTAssertTrue(signature.isVerified)
            XCTAssertEqual("Sample Subject", signature.certificate.subject.commonName)
            XCTAssertEqual("Sample Issuer", signature.certificate.issuer.commonName)
        }
    }

    func testMissingRequiredSignature() throws {
        try fixture(name: "Collections", createGitRepo: false) { fixturePath in
            let path = fixturePath.appending(components: "JSON", "good.json")
            let url = URL(string: "https://www.test.com/collection.json")!
            let data: Data = try localFileSystem.readFileContents(path)

            let handler: HTTPClient.Handler = { request, _, completion in
                XCTAssertEqual(request.url, url, "url should match")
                switch request.method {
                case .head:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]))))
                case .get:
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none

            // The validator doesn't know about the test collection so its signature would be considered invalid
            let signatureValidator = MockCollectionSignatureValidator()
            // Collections from www.test.com must be signed
            let sourceCertPolicy = PackageCollectionSourceCertificatePolicy(
                sourceCertPolicies: ["www.test.com": [.init(certPolicyKey: CertificatePolicyKey.default, base64EncodedRootCerts: nil)]]
            )
            let provider = JSONPackageCollectionProvider(httpClient: httpClient, signatureValidator: signatureValidator,
                                                         sourceCertPolicy: sourceCertPolicy)
            let source = PackageCollectionsModel.CollectionSource(type: .json, url: url)

            XCTAssertThrowsError(try tsc_await { callback in provider.get(source, callback: callback) }, "expected error", { error in
                switch error {
                case PackageCollectionError.missingSignature:
                    break
                default:
                    XCTFail("unexpected error \(error)")
                }
            })
        }
    }
}

private extension XCTestCase {
    func skipIfSignatureCheckNotSupported() throws {
        if !JSONPackageCollectionProvider.isSignatureCheckSupported {
            throw XCTSkip("Skipping test because signature check is not supported")
        }
    }
}

internal extension JSONPackageCollectionProvider {
    init(
        configuration: Configuration = .init(),
        httpClient: HTTPClient? = nil,
        signatureValidator: PackageCollectionSignatureValidator? = nil,
        sourceCertPolicy: PackageCollectionSourceCertificatePolicy = PackageCollectionSourceCertificatePolicy(),
        fileSystem: FileSystem = localFileSystem
    ) {
        self.init(
            configuration: configuration,
            fileSystem: fileSystem,
            observabilityScope: ObservabilitySystem.NOOP,
            sourceCertPolicy: sourceCertPolicy,
            customHTTPClient: httpClient ,
            customSignatureValidator: signatureValidator
        )
    }
}
