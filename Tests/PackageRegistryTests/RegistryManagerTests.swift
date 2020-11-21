/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import SPMTestSupport
import TSCBasic

import Basics
import PackageLoading
import PackageModel
@testable import PackageRegistry

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RegistryManagerTests: XCTestCase {
    private let queue = DispatchQueue(label: "org.swift.registry.tests")

    class override func setUp() {
        PackageModel._useLegacyIdentities = false

        RegistryManager.archiverFactory = { _ in
            return MockArchiver()
        }

        RegistryManager.clientFactory = { diagnosticsEngine in
            let configuration = HTTPClientConfiguration()
            let handler: HTTPClient.Handler = { request, completion in
                var headers: HTTPClientHeaders = [
                    "Content-Version": "1",
                ]

                let result: Result<HTTPClientResponse, Error>
                switch (request.method, request.url.absoluteString.lowercased()) {
                case (.head, "https://github.com/mona/linkedlist"):
                    headers.add(name: "Location", value: "https://pkg.swift.github.com/github.com/mona/LinkedList")

                    result = .success(HTTPClientResponse(statusCode: 303, headers: headers, body: nil))
                case (.get, "https://pkg.swift.github.com/github.com/mona/linkedlist"):
                    let data = #"""
                    {
                        "releases": {
                            "1.1.1": {
                                "url": "https://packages.example.com/mona/LinkedList/1.1.1"
                            },
                            "1.1.0": {
                                "url": "https://packages.example.com/mona/LinkedList/1.1.0",
                                "problem": {
                                    "status": 410,
                                    "title": "Gone",
                                    "detail": "this release was removed from the registry"
                                }
                            },
                            "1.0.0": {
                                "url": "https://packages.example.com/mona/LinkedList/1.0.0"
                            }
                        }
                    }

                    """#.data(using: .utf8)!

                    headers.add(name: "Content-Type", value: "application/json")
                    headers.add(name: "Content-Length", value: "\(data.count)")

                    result = .success(HTTPClientResponse(statusCode: 200, headers: headers, body: data))
                case (.get, "https://pkg.swift.github.com/github.com/mona/linkedlist/1.1.1/package.swift"):
                    let data = #"""
                    // swift-tools-version:5.0
                    import PackageDescription

                    let package = Package(
                        name: "LinkedList",
                        products: [
                            .library(name: "LinkedList", targets: ["LinkedList"])
                        ],
                        targets: [
                            .target(name: "LinkedList"),
                            .testTarget(name: "LinkedListTests", dependencies: ["LinkedList"]),
                        ],
                        swiftLanguageVersions: [.v4, .v5]
                    )

                    """#.data(using: .utf8)!

                    headers.add(name: "Content-Type", value: "text/x-swift")
                    headers.add(name: "Content-Disposition", value: #"attachment; filename="Package.swift""#)
                    headers.add(name: "Content-Length", value: "\(data.count)")

                    result = .success(HTTPClientResponse(statusCode: 200, headers: headers, body: data))
                case (.get, "https://pkg.swift.github.com/github.com/mona/linkedlist/1.1.1.zip"):
                    let archive = emptyZipFile

                    headers.add(name: "Content-Type", value: "application/zip")
                    headers.add(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#)
                    headers.add(name: "Content-Length", value: "22")
                    headers.add(name: "Digest", value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283")

                    result = .success(HTTPClientResponse(statusCode: 200, headers: headers, body: Data(archive.contents)))
                default:
                    result = .failure(StringError("Unhandled request: \(request)"))
                }

                completion(result)
            }

            return HTTPClient(configuration: configuration, handler: handler, diagnosticsEngine: diagnosticsEngine)
        }

        super.setUp()
    }

    func testDiscoverPackageRegistry() {
        let identity = PackageIdentity(url: "https://github.com/mona/LinkedList")
        let package = PackageReference(identity: identity, path: "/LinkedList")
        let expectation = XCTestExpectation(description: "discover package registry")

        RegistryManager.discover(for: package, on: queue) { result in
            defer { expectation.fulfill() }

            XCTAssertResultSuccess(result)
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testFetchVersions() {
        let identity = PackageIdentity(url: "https://github.com/mona/LinkedList")
        let package = PackageReference(identity: identity, path: "/LinkedList")
        let expectation = XCTestExpectation(description: "discover package registry")
        let nestedExpectation = XCTestExpectation(description: "fetch versions")

        RegistryManager.discover(for: package, on: queue) { result in
            defer { expectation.fulfill() }
            guard case .success(let manager) = result else {
                return XCTAssertResultSuccess(result)
            }

            manager.fetchVersions(of: package) { result in
                defer { nestedExpectation.fulfill() }

                guard case .success(let versions) = result else {
                    return XCTAssertResultSuccess(result)
                }

                XCTAssertEqual(versions, ["1.1.1", "1.0.0"])
                XCTAssertFalse(versions.contains("1.1.0"), "problematic releases shouldn't be included")
            }
        }

        wait(for: [expectation, nestedExpectation], timeout: 10.0)
    }

    func testFetchManifest() {
        let identity = PackageIdentity(url: "https://github.com/mona/LinkedList")
        let package = PackageReference(identity: identity, path: "/LinkedList")
        let expectation = XCTestExpectation(description: "discover package registry")
        let nestedExpectation = XCTestExpectation(description: "fetch manifest")

        RegistryManager.discover(for: package, on: queue) { result in
            defer { expectation.fulfill() }
            guard case .success(let manager) = result else {
                return XCTAssertResultSuccess(result)
            }

            let manifestLoader = ManifestLoader(manifestResources: Resources.default)

            manager.fetchManifest(for: "1.1.1", of: package, using: manifestLoader) { result in
                defer { nestedExpectation.fulfill() }

                guard case .success(let manifest) = result else {
                    return XCTAssertResultSuccess(result)
                }

                XCTAssertEqual(manifest.name, "LinkedList")

                XCTAssertEqual(manifest.products.count, 1)
                XCTAssertEqual(manifest.products.first?.name, "LinkedList")
                XCTAssertEqual(manifest.products.first?.type, .library(.automatic))

                XCTAssertEqual(manifest.targets.count, 2)
                XCTAssertEqual(manifest.targets.first?.name, "LinkedList")
                XCTAssertEqual(manifest.targets.first?.type, .regular)
                XCTAssertEqual(manifest.targets.last?.name, "LinkedListTests")
                XCTAssertEqual(manifest.targets.last?.type, .test)

                XCTAssertEqual(manifest.swiftLanguageVersions, [.v4, .v5])
            }
        }

        wait(for: [expectation, nestedExpectation], timeout: 10.0)
    }

    func testDownloadSourceArchive() {
        let identity = PackageIdentity(url: "https://github.com/mona/LinkedList")
        let package = PackageReference(identity: identity, path: "/LinkedList")
        let expectation = XCTestExpectation(description: "discover package registry")
        let nestedExpectation = XCTestExpectation(description: "download source archive")

        RegistryManager.discover(for: package, on: queue) { result in
            defer { expectation.fulfill() }
            guard case .success(let manager) = result else {
                return XCTAssertResultSuccess(result)
            }

            let fs = InMemoryFileSystem()
            let path = AbsolutePath("/LinkedList-1.1.1")
            manager.downloadSourceArchive(for: "1.1.1", of: package, into: fs, at: path) { result in
                defer { nestedExpectation.fulfill() }

                guard case .success = result else { return XCTAssertResultSuccess(result) }

                XCTAssertNoThrow {
                    let data = try fs.readFileContents(path)
                    XCTAssertEqual(data, emptyZipFile)
                }
            }
        }

        wait(for: [expectation, nestedExpectation], timeout: 10.0)
    }
}
