/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageLoading
import PackageModel
import PackageRegistry
import SPMTestSupport
import TSCBasic
import XCTest

final class RegistryClientTests: XCTestCase {
    func testFetchVersions() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let releasesURL = URL(string: "\(registryURL)/\(scope)/\(name)")!

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, releasesURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

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

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { _ in MockArchiver() },
            customHTTPClient: httpClient
        )

        let versions = try registryManager.fetchVersions(package: identity)
        XCTAssertEqual(["1.1.1", "1.0.0"], versions)
    }

    func testAvailableManifests() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let version = Version("1.1.1")
        let manifestURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version)/Package.swift")!

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, manifestURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+swift")

                let data = #"""
                // swift-tools-version:5.5
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

                let links = """
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.2",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=5.3>; rel="alternate"; filename="Package@swift-5.3.swift"; swift-tools-version="5.3"
                """

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { _ in MockArchiver() },
            customHTTPClient: httpClient
        )

        let availableManifests = try registryManager.getAvailableManifests(
            package: identity,
            version: version
        )
        XCTAssertEqual(availableManifests,
            [
                "Package.swift": .v5_5,
                "Package@swift-4.swift": .v4,
                "Package@swift-4.2.swift": .v4_2,
                "Package@swift-5.3.swift": .v5_3,
            ]
        )
    }

    func testGetManifestContent() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let version = Version("1.1.1")
        let manifestURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version)/Package.swift")!

        let handler: HTTPClient.Handler = { request, _, completion in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first{ $0.name == "swift-version" }.flatMap{ ToolsVersion(string: $0.value!) } ?? ToolsVersion.currentToolsVersion
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, manifestURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+swift")

                let data = """
                // swift-tools-version:\(toolsVersion)

                import PackageDescription

                let package = Package()
                """.data(using: .utf8)!

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1")
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { _ in MockArchiver() },
            customHTTPClient: httpClient
        )

        do {
            let manifest = try registryManager.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: nil
            )
            let toolsVersionLoader = ToolsVersionLoader()
            let parsedToolsVersion = try toolsVersionLoader.load(utf8String: manifest)
            XCTAssertEqual(parsedToolsVersion, .currentToolsVersion)
        }

        do {
            let manifest = try registryManager.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: .v5_3
            )
            let toolsVersionLoader = ToolsVersionLoader()
            let parsedToolsVersion = try toolsVersionLoader.load(utf8String: manifest)
            XCTAssertEqual(parsedToolsVersion, .v5_3)
        }

        do {
            let manifest = try registryManager.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: .v4
            )
            let toolsVersionLoader = ToolsVersionLoader()
            let parsedToolsVersion = try toolsVersionLoader.load(utf8String: manifest)
            XCTAssertEqual(parsedToolsVersion, .v4)
        }
    }

    func testFetchSourceArchiveChecksum() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let version = Version("1.1.1")
        let metadataURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version)")!

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

                let data = #"""
                {
                    "id": "mona.LinkedList",
                    "version": "1.1.1",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"
                        }
                    ],
                    "metadata": {
                        "description": "One thing links to another."
                    }
                }
                """#.data(using: .utf8)!

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { _ in MockArchiver() },
            customHTTPClient: httpClient
        )

        let checksum = try registryManager.fetchSourceArchiveChecksum(package: identity, version: version)
        XCTAssertEqual("a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812", checksum)
    }

    func testDownloadSourceArchiveWithExpectedChecksumProvided() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let version = Version("1.1.1")
        let downloadURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version).zip")!

        let checksumAlgorithm: HashAlgorithm = SHA256()
        let expectedChecksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.kind,  request.method, request.url) {
            case (.download(let fileSystem, let path), .get, downloadURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(name: "Digest", value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"),
                    ]),
                    body: nil
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    XCTAssertEqual(data, emptyZipFile)

                    let packagePath = to.appending(component: "package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending(component: "Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            customHTTPClient: httpClient
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        try registryManager.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path,
            expectedChecksum: expectedChecksum,
            checksumAlgorithm: checksumAlgorithm
        )

        let contents = try fileSystem.getDirectoryContents(path)
        XCTAssertEqual(contents, ["Package.swift"])
    }

    func testDownloadSourceArchiveWithoutExpectedChecksumProvided() throws {
        let registryURL = "https://packages.example.com"
        let identity = PackageIdentity.plain("mona.LinkedList")
        let (scope, name) = identity.scopeAndName!
        let version = Version("1.1.1")
        let downloadURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version).zip")!
        let metadataURL = URL(string: "\(registryURL)/\(scope)/\(name)/\(version)")!

        let checksumAlgorithm: HashAlgorithm = SHA256()

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.kind, request.method, request.url) {
            case (.download(let fileSystem, let path), .get, downloadURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(name: "Digest", value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"),
                    ]),
                    body: nil
                )))
                // `downloadSourceArchive` calls this API to fetch checksum
            case (.generic, .get, metadataURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

                let data = """
                {
                  "id": "mona.LinkedList",
                  "version": "1.1.1",
                  "resources": [
                    {
                      "name": "source-archive",
                      "type": "application/zip",
                      "checksum": "\(checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation)"
                    }
                  ],
                  "metadata": {
                    "description": "One thing links to another."
                  }
                }
                """.data(using: .utf8)!

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    XCTAssertEqual(data, emptyZipFile)

                    let packagePath = to.appending(component: "package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending(component: "Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            customHTTPClient: httpClient
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        try registryManager.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path,
            expectedChecksum: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let contents = try fileSystem.getDirectoryContents(path)
        XCTAssertEqual(contents, ["Package.swift"])
    }

    func testLookupIdentities() throws {
        let registryURL = "https://packages.example.com"
        let packageURL = URL(string: "https://example.com/mona/LinkedList")!
        let identifiersURL = URL(string: "\(registryURL)/identifiers?url=\(packageURL.absoluteString)")!

        let handler: HTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, identifiersURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

                let data = #"""
                {
                    "identifiers": [
                      "mona.LinkedList"
                    ]
                }
                """#.data(using: .utf8)!

                completion(.success(.init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )))
            default:
                completion(.failure(StringError("method and url should match")))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: URL(string: registryURL)!)

        let registryManager = RegistryClient(
            configuration: configuration,
            identityResolver: DefaultIdentityResolver(),
            customArchiverProvider: { _ in MockArchiver() },
            customHTTPClient: httpClient
        )

        let identities = try registryManager.lookupIdentities(url: packageURL)
        XCTAssertEqual([PackageIdentity.plain("mona.LinkedList")], identities)
    }
}

// MARK - Sugar

extension RegistryClient {
    public func fetchVersions(package: PackageIdentity) throws -> [Version] {
        return try tsc_await {
            self.fetchVersions(
                package: package,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }

    public func getAvailableManifests(
        package: PackageIdentity,
        version: Version
    ) throws -> [String : ToolsVersion] {
        return try tsc_await {
            self.getAvailableManifests(
                package: package,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }

    public func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?
    ) throws -> String {
        return try tsc_await {
            self.getManifestContent(
                package: package,
                version: version,
                customToolsVersion: customToolsVersion,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }

    public func fetchSourceArchiveChecksum(package: PackageIdentity, version: Version) throws -> String {
        return try tsc_await {
            self.fetchSourceArchiveChecksum(
                package: package,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }

    public func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        expectedChecksum: String?,
        checksumAlgorithm: HashAlgorithm
    ) throws -> Void {
        return try tsc_await {
            self.downloadSourceArchive(
                package: package,
                version: version,
                fileSystem: fileSystem,
                destinationPath: destinationPath,
                expectedChecksum: expectedChecksum,
                checksumAlgorithm: checksumAlgorithm,
                progressHandler: .none,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }

    public func lookupIdentities(url: Foundation.URL) throws -> Set<PackageIdentity> {
        return try tsc_await {
            self.lookupIdentities(
                url: url,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }
}
