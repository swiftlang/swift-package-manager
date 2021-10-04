/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
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
    private var registryManager: RegistryManager!

    class override func setUp() {
        RegistryManager.archiverFactory = { _ in
            return MockArchiver()
        }

        super.setUp()
    }

    override func setUp() {
        let identityResolver = DefaultIdentityResolver()

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: "https://packages.example.com/")!)

        registryManager = RegistryManager(configuration: configuration,
                                          identityResolver: identityResolver)
    }

    // MARK: -

    func testFetchVersions() {
        let identity: PackageIdentity = .plain("mona.LinkedList")
        let package = PackageReference(identity: identity, kind: .registry(identity))

        registryManager.client = HTTPClient { request, _, completion in
            XCTAssertEqual(request.url.absoluteString, "https://packages.example.com/mona/LinkedList")
            XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

            let body = #"""
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

            let headers: HTTPClientHeaders = [
                "Content-Version": "1",
                "Content-Type": "application/json",
                "Content-Length": "\(body.count)"
            ]

            let response = HTTPClientResponse(statusCode: 200, headers: headers, body: body)

            completion(.success(response))
        }

        let expectation = XCTestExpectation(description: "fetch versions")

        registryManager.fetchVersions(of: package, on: .sharedConcurrent) { result in
            defer { expectation.fulfill() }

            guard case .success(let versions) = result else {
                return XCTAssertResultSuccess(result)
            }

            XCTAssertEqual(versions, ["1.1.1", "1.0.0"])
            XCTAssertFalse(versions.contains("1.1.0"), "problematic releases shouldn't be included")
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testFetchManifest() {
        let identity: PackageIdentity = .plain("mona.LinkedList")
        let package = PackageReference(identity: identity, kind: .registry(identity))

        registryManager.client = HTTPClient { request, _, completion in
            XCTAssertEqual(request.url.absoluteString, "https://packages.example.com/mona/LinkedList/1.1.1/Package.swift")
            XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+swift")

            let body = #"""
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

            let headers: HTTPClientHeaders = [
                "Content-Version": "1",
                "Content-Disposition": #"attachment; filename="Package.swift""#,
                "Content-Type": "text/x-swift",
                "Content-Length": "\(body.count)"
            ]

            let response = HTTPClientResponse(statusCode: 200, headers: headers, body: body)

            completion(.success(response))
        }

        let expectation = XCTestExpectation(description: "fetch manifest")

        let manifestLoader = ManifestLoader(toolchain: .default)
        registryManager.fetchManifest(for: "1.1.1", of: package, using: manifestLoader, on: .sharedConcurrent) { result in
            defer { expectation.fulfill() }

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
        wait(for: [expectation], timeout: 10.0)
    }

    func testDownloadSourceArchive() {
        let identity: PackageIdentity = .plain("mona.LinkedList")
        let package = PackageReference(identity: identity, kind: .registry(identity))

        registryManager.client = HTTPClient { request, _, completion in
            XCTAssertEqual(request.url.absoluteString, "https://packages.example.com/mona/LinkedList/1.1.1.zip")
            XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+zip")

            let body = Data(emptyZipFile.contents)

            let headers: HTTPClientHeaders = [
                "Content-Version": "1",
                "Content-Disposition": #"attachment; filename="LinkedList-1.1.1.zip""#,
                "Content-Type": "application/zip",
                "Content-Length": "\(body.count)",
                "Digest": "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
            ]

            let response = HTTPClientResponse(statusCode: 200, headers: headers, body: body)

            completion(.success(response))
        }

        let expectation = XCTestExpectation(description: "download source archive")

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")
        registryManager.downloadSourceArchive(for: "1.1.1", of: package, into: fileSystem, at: path, on: .sharedConcurrent) { result in
            defer { expectation.fulfill() }

            guard case .success = result else { return XCTAssertResultSuccess(result) }

            XCTAssertNoThrow {
                let data = try fileSystem.readFileContents(path)
                XCTAssertEqual(data, emptyZipFile)
            }
        }
        wait(for: [expectation], timeout: 10.0)
    }
}
