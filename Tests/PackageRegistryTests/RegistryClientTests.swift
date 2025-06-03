//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Foundation
import PackageFingerprint
import PackageLoading
import PackageModel
@testable import PackageRegistry
import PackageSigning
import _InternalTestSupport
import Testing

import protocol TSCBasic.HashAlgorithm
import struct TSCUtility.Version

fileprivate let registryURL = URL("https://packages.example.com")
fileprivate let identity = PackageIdentity.plain("mona.LinkedList")
fileprivate let version = Version("1.1.1")
fileprivate let packageURL = SourceControlURL("https://example.com/mona/LinkedList")
fileprivate var releasesURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)")
fileprivate var releaseURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")
fileprivate var metadataURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")
fileprivate var manifestURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)/Package.swift")
fileprivate var downloadURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version).zip")
fileprivate var identifiersURL = URL("\(registryURL)/identifiers?url=\(packageURL.absoluteString)")
fileprivate var publishURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")
fileprivate var availabilityURL = URL("\(registryURL)/availability")

@Suite("Package Metadata") struct PackageMetadata {
    @Test func getPackageMetadata() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, releasesURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

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

                let links = """
                <https://github.com/mona/LinkedList>; rel="canonical",
                <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
                <git@github.com:mona/LinkedList.git>; rel="alternate",
                <https://gitlab.com/mona/LinkedList>; rel="alternate"
                """

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let assert: (RegistryClient.PackageMetadata) -> Void = { metadata in
            #expect(metadata.versions == ["1.1.1", "1.0.0"])
            #expect(metadata.alternateLocations == [
                SourceControlURL("https://github.com/mona/LinkedList"),
                SourceControlURL("ssh://git@github.com:mona/LinkedList.git"),
                SourceControlURL("git@github.com:mona/LinkedList.git"),
                SourceControlURL("https://gitlab.com/mona/LinkedList"),
            ])
        }

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        let metadata = try await registryClient.getPackageMetadata(package: identity)
        assert(metadata)

        let metadataSync = try await withCheckedThrowingContinuation { continuation in
            return registryClient.getPackageMetadata(
                package: identity,
                timeout: nil,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
        assert(metadataSync)
    }

    @Test func getPackageMetadataPaginated() async throws {
        let releasesURLPage2 = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)?page=2")

        let handler: HTTPClient.Implementation = { request, _ in
            guard case .get = request.method else {
                throw StringError("method should be `get`")
            }

            #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
            let links: String
            let data: Data
            switch request.url {
            case releasesURL:
                data = #"""
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
                        }
                    }
                }
                """#.data(using: .utf8)!

                links = """
                <https://github.com/mona/LinkedList>; rel="canonical",
                <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
                <git@github.com:mona/LinkedList.git>; rel="alternate",
                <https://gitlab.com/mona/LinkedList>; rel="alternate",
                <\(releasesURLPage2)>; rel="next"
                """
            case releasesURLPage2:
                data = #"""
                {
                    "releases": {
                        "1.0.0": {
                            "url": "https://packages.example.com/mona/LinkedList/1.0.0"
                        }
                    }
                }
                """#.data(using: .utf8)!

                links = """
                <https://github.com/mona/LinkedList>; rel="canonical",
                <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
                <git@github.com:mona/LinkedList.git>; rel="alternate",
                <https://gitlab.com/mona/LinkedList>; rel="alternate"
                """
            default:
                throw StringError("method and url should match")
            }

            return .init(
                statusCode: 200,
                headers: .init([
                    .init(name: "Content-Length", value: "\(data.count)"),
                    .init(name: "Content-Type", value: "application/json"),
                    .init(name: "Content-Version", value: "1"),
                    .init(name: "Link", value: links),
                ]),
                body: data
            )
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        let metadata = try await registryClient.getPackageMetadata(package: identity)
        #expect(metadata.versions == ["1.1.1", "1.0.0"])
        #expect(metadata.alternateLocations == [
            SourceControlURL("https://github.com/mona/LinkedList"),
            SourceControlURL("ssh://git@github.com:mona/LinkedList.git"),
            SourceControlURL("git@github.com:mona/LinkedList.git"),
            SourceControlURL("https://gitlab.com/mona/LinkedList"),
        ])
    }

    @Test func getPackageMetadataPaginatedCancellation() async throws {
        let releasesURLPage2 = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)?page=2")

        var task: Task<Void, Error>? = nil
        let handler: HTTPClient.Implementation = { request, _ in
            guard case .get = request.method else {
                throw StringError("method should be `get`")
            }

            #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
            let links: String
            let data: Data
            switch request.url {
            case releasesURLPage2:
                // Cancel during the second iteration
                task?.cancel()
                fallthrough
            case releasesURL:
                data = #"""
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
                        }
                    }
                }
                """#.data(using: .utf8)!

                links = """
                <https://github.com/mona/LinkedList>; rel="canonical",
                <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
                <git@github.com:mona/LinkedList.git>; rel="alternate",
                <https://gitlab.com/mona/LinkedList>; rel="alternate",
                <\(releasesURLPage2)>; rel="next"
                """
            default:
                throw StringError("method and url should match")
            }

            return .init(
                statusCode: 200,
                headers: .init([
                    .init(name: "Content-Length", value: "\(data.count)"),
                    .init(name: "Content-Type", value: "application/json"),
                    .init(name: "Content-Version", value: "1"),
                    .init(name: "Link", value: links),
                ]),
                body: data
            )
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)

        task = Task {
            await #expect(throws: _Concurrency.CancellationError.self) {
                try await registryClient.getPackageMetadata(package: identity)
            }
        }

        try await task?.value
    }

    @Test func handlesNotFound() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: releasesURL,
            errorCode: 404,
            errorDescription: UUID().uuidString
        )

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageMetadata(package: identity)
        } throws: { error in
            if case RegistryError.failedRetrievingReleases(
                registry: configuration.defaultRegistry!,
                package: identity,
                error: RegistryError.packageNotFound
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesServerError() async throws {
        let releasesURL = URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)")

        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: releasesURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageMetadata(package: identity)
        } throws: { error in
            if case RegistryError
                .failedRetrievingReleases(
                    registry: configuration.defaultRegistry!,
                    package: identity,
                    error: RegistryError.serverError(
                        code: serverErrorHandler.errorCode,
                        details: serverErrorHandler.errorDescription
                    )
                ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesRegistryNotAvailable() async throws {
        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageMetadata(package: identity)
        } throws: { error in
            if case RegistryError.registryNotAvailable(registry) = error {
                return true
            }
            return false
        }
    }
}

@Suite("Package Version Metadata") struct PackageVersionMetadata {
    @Test func getPackageVersionMetadata() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, releaseURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

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
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """#.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let assert: (RegistryClient.PackageVersionMetadata) -> Void = { metadata in
            #expect(metadata.resources.count == 1)
            #expect(metadata.resources[0].name == "source-archive")
            #expect(metadata.resources[0].type == "application/zip")
            #expect(metadata.resources[0].checksum == "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812")
            #expect(metadata.author?.name == "J. Appleseed")
            #expect(metadata.licenseURL == URL("https://github.com/mona/LinkedList/license"))
            #expect(metadata.readmeURL == URL("https://github.com/mona/LinkedList/readme"))
            #expect(metadata.repositoryURLs! == [
                SourceControlURL("https://github.com/mona/LinkedList"),
                SourceControlURL("ssh://git@github.com:mona/LinkedList.git"),
                SourceControlURL("git@github.com:mona/LinkedList.git"),
            ])
        }

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        let metadata = try await registryClient.getPackageVersionMetadata(package: identity, version: version)
        assert(metadata)

        let metadataSync = try await withCheckedThrowingContinuation { continuation in
            return registryClient.getPackageVersionMetadata(
                package: identity,
                version: version,
                fileSystem: InMemoryFileSystem(),
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
        assert(metadataSync)
    }

    func getPackageVersionMetadata_404() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: releaseURL,
            errorCode: 404,
            errorDescription: UUID().uuidString
        )

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageVersionMetadata(package: identity, version: version)
        } throws: { error in
            if case RegistryError
                .failedRetrievingReleaseInfo(
                    registry: configuration.defaultRegistry!,
                    package: identity,
                    version: version,
                    error: RegistryError.packageVersionNotFound
                ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesServerError() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: releaseURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageVersionMetadata(package: identity, version: version)
        } throws: { error in
            if case RegistryError
                .failedRetrievingReleaseInfo(
                    registry: configuration.defaultRegistry!,
                    package: identity,
                    version: version,
                    error: RegistryError.serverError(
                        code: serverErrorHandler.errorCode,
                        details: serverErrorHandler.errorDescription
                    )
                ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesRegistryNotAvailable() async throws {
        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getPackageVersionMetadata(package: identity, version: version)
        } throws: { error in
            if case RegistryError.registryNotAvailable(registry) = error {
                return true
            }
            return false
        }
    }
}

@Suite("Available Manifests") struct AvailabileManifests {
    var metadataURL: URL { URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)") }
    var manifestURL: URL {
        URL("\(registryURL)/\(identity.registry!.scope)/\(identity.registry!.name)/\(version)/Package.swift")
    }
    @Test func availableManifests() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let defaultManifest = """
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
        """

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let defaultManifestData = Data(defaultManifest.utf8)

                let links = """
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.2",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=5.3>; rel="alternate"; filename="Package@swift-5.3.swift"; swift-tools-version="5.3"
                """

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(defaultManifestData.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: defaultManifestData
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            checksumAlgorithm: checksumAlgorithm
        )

        let assert: ([String: (toolsVersion: ToolsVersion, content: String?)]) -> Void = { availableManifests in
            #expect(availableManifests["Package.swift"]?.toolsVersion == .v5_5)
            #expect(availableManifests["Package.swift"]?.content == defaultManifest)
            #expect(availableManifests["Package@swift-4.swift"]?.toolsVersion == .v4)
            #expect(availableManifests["Package@swift-4.swift"]?.content == .none)
            #expect(availableManifests["Package@swift-4.2.swift"]?.toolsVersion == .v4_2)
            #expect(availableManifests["Package@swift-4.2.swift"]?.content == .none)
            #expect(availableManifests["Package@swift-5.3.swift"]?.toolsVersion == .v5_3)
            #expect(availableManifests["Package@swift-5.3.swift"]?.content == .none)
        }

        let availableManifests = try await registryClient.getAvailableManifests(
            package: identity,
            version: version,
            observabilityScope: ObservabilitySystem.NOOP
        )
        assert(availableManifests)

        let availableManifestsSync = try await withCheckedThrowingContinuation { continuation in
            return registryClient.getAvailableManifests(
                package: identity,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
        assert(availableManifestsSync)
    }

    @Test func availableManifestsMatchingChecksumInStorage() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let defaultManifest = """
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
        """

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let defaultManifestData = Data(defaultManifest.utf8)

                let links = """
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.2",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=5.3>; rel="alternate"; filename="Package@swift-5.3.swift"; swift-tools-version="5.3"
                """

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(defaultManifestData.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: defaultManifestData
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let contentType = Fingerprint.ContentType.manifest(.none)
        let manifestChecksum = checksumAlgorithm.hash(.init(Data(defaultManifest.utf8)))
            .hexadecimalRepresentation
        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        contentType: Fingerprint(
                            origin: .registry(registryURL),
                            value: manifestChecksum,
                            contentType: contentType
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            checksumAlgorithm: checksumAlgorithm
        )
        let availableManifests = try await registryClient.getAvailableManifests(
            package: identity,
            version: version,
            observabilityScope: ObservabilitySystem.NOOP
        )

        #expect(availableManifests["Package.swift"]?.toolsVersion == .v5_5)
        #expect(availableManifests["Package.swift"]?.content == defaultManifest)
        #expect(availableManifests["Package@swift-4.swift"]?.toolsVersion == .v4)
        #expect(availableManifests["Package@swift-4.swift"]?.content == .none)
        #expect(availableManifests["Package@swift-4.2.swift"]?.toolsVersion == .v4_2)
        #expect(availableManifests["Package@swift-4.2.swift"]?.content == .none)
        #expect(availableManifests["Package@swift-5.3.swift"]?.toolsVersion == .v5_3)
        #expect(availableManifests["Package@swift-5.3.swift"]?.content == .none)
    }

    @Test func availableManifestsNonMatchingChecksumInStorage_strict() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let defaultManifest = """
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
        """

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let defaultManifestData = Data(defaultManifest.utf8)

                let links = """
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.2",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=5.3>; rel="alternate"; filename="Package@swift-5.3.swift"; swift-tools-version="5.3"
                """

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(defaultManifestData.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: defaultManifestData
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let contentType = Fingerprint.ContentType.manifest(.none)
        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        contentType: Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: contentType
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict, // intended for this test; don't change
            checksumAlgorithm: checksumAlgorithm
        )

        await #expect {
            try await registryClient.getAvailableManifests(
                package: identity,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP
            )
        } throws: { error in
            if case RegistryError.invalidChecksum = error {
                return true
            }
            return false
        }
    }

    @Test func availableManifestsNonMatchingChecksumInStorage_warn() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let defaultManifest = """
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
        """

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let defaultManifestData = Data(defaultManifest.utf8)

                let links = """
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.2",
                <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=5.3>; rel="alternate"; filename="Package@swift-5.3.swift"; swift-tools-version="5.3"
                """

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(defaultManifestData.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Link", value: links),
                    ]),
                    body: defaultManifestData
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let contentType = Fingerprint.ContentType.manifest(.none)
        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        contentType: Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: contentType
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .warn, // intended for this test; don't change
            checksumAlgorithm: checksumAlgorithm
        )

        let observability = ObservabilitySystem.makeForTesting()
        // The checksum differs from that in storage, but error is not thrown
        // because fingerprintCheckingMode=.warn
        let availableManifests = try await registryClient.getAvailableManifests(
            package: identity,
            version: version,
            observabilityScope: observability.topScope
        )

        // But there should be a warning
        try expectDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }

        #expect(availableManifests["Package.swift"]?.toolsVersion == .v5_5)
        #expect(availableManifests["Package.swift"]?.content == defaultManifest)
        #expect(availableManifests["Package@swift-4.swift"]?.toolsVersion == .v4)
        #expect(availableManifests["Package@swift-4.swift"]?.content == .none)
        #expect(availableManifests["Package@swift-4.2.swift"]?.toolsVersion == .v4_2)
        #expect(availableManifests["Package@swift-4.2.swift"]?.content == .none)
        #expect(availableManifests["Package@swift-5.3.swift"]?.toolsVersion == .v5_3)
        #expect(availableManifests["Package@swift-5.3.swift"]?.content == .none)
    }

    @Test func handles404() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: manifestURL,
            errorCode: 404,
            errorDescription: "not found"
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getAvailableManifests(
                package: identity,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP
            )
        } throws: { error in
            if case RegistryError.failedRetrievingManifest(
                registry: configuration.defaultRegistry!,
                package: identity,
                version: version,
                error: RegistryError.packageVersionNotFound
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesServerError() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: manifestURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getAvailableManifests(
                package: identity,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP
            )
        } throws: { error in
            if case RegistryError.failedRetrievingManifest(
                registry: configuration.defaultRegistry!,
                package: identity,
                version: version,
                error: RegistryError.serverError(
                    code: serverErrorHandler.errorCode,
                    details: serverErrorHandler.errorDescription
                )
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesRegistryNotAvailable() async throws {
        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getAvailableManifests(
                package: identity,
                version: version,
                observabilityScope: ObservabilitySystem.NOOP
            )
        } throws: { error in
            if case RegistryError.registryNotAvailable(registry) = error {
                return true
            }
            return false
        }
    }
}

@Suite("Manifest Content") struct ManifestContent {
    @Test(arguments: [
        (toolsVersion: ToolsVersion.v5_3, expectedToolsVersion: ToolsVersion.v5_3),
        (toolsVersion: ToolsVersion.v4, expectedToolsVersion: ToolsVersion.v4),
        (toolsVersion: nil, expectedToolsVersion: ToolsVersion.current)
    ])
    func getManifestContent(toolsVersion: ToolsVersion?, expectedToolsVersion: ToolsVersion) async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first { $0.name == "swift-version" }
                .flatMap { ToolsVersion(string: $0.value!) } ?? ToolsVersion.current
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let data = """
                // swift-tools-version:\(toolsVersion)

                import PackageDescription

                let package = Package()
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            checksumAlgorithm: checksumAlgorithm
        )

        do {
            let manifest = try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: toolsVersion
            )
            let parsedToolsVersion = try ToolsVersionParser.parse(utf8String: manifest)
            #expect(parsedToolsVersion == expectedToolsVersion)
        }

        do {
            let manifestSync = try await withCheckedThrowingContinuation { continuation in
                return registryClient.getManifestContent(
                    package: identity,
                    version: version,
                    customToolsVersion: toolsVersion,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: .sharedConcurrent
                ) { continuation.resume(with: $0) }
            }
            let parsedToolsVersion = try ToolsVersionParser.parse(utf8String: manifestSync)
            #expect(parsedToolsVersion == expectedToolsVersion)
        }
    }

    @Test(arguments: [
        (toolsVersion: ToolsVersion.v5_3, expectedToolsVersion: ToolsVersion.v5_3),
        (toolsVersion: nil, expectedToolsVersion: ToolsVersion.current)
    ])
    func getManifestContentWithOptionalContentVersion(toolsVersion: ToolsVersion?, expectedToolsVersion: ToolsVersion) async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first { $0.name == "swift-version" }
                .flatMap { ToolsVersion(string: $0.value!) } ?? ToolsVersion.current
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let data = """
                // swift-tools-version:\(toolsVersion)

                import PackageDescription

                let package = Package()
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        // Omit `Content-Version` header
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            checksumAlgorithm: checksumAlgorithm
        )

        do {
            let manifest = try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: toolsVersion
            )
            let parsedToolsVersion = try ToolsVersionParser.parse(utf8String: manifest)
            #expect(parsedToolsVersion == expectedToolsVersion)
        }
    }

    @Test(arguments: [
        (toolsVersion: ToolsVersion.v5_3, expectedToolsVersion: ToolsVersion.v5_3),
        (toolsVersion: nil, expectedToolsVersion: ToolsVersion.current)
    ])
    func getManifestContentMatchingChecksumInStorage(toolsVersion: ToolsVersion?, expectedToolsVersion: ToolsVersion) async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first { $0.name == "swift-version" }
                .flatMap { ToolsVersion(string: $0.value!) } ?? ToolsVersion.current
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let data = Data(manifestContent(toolsVersion: toolsVersion).utf8)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let defaultManifestChecksum = checksumAlgorithm
            .hash(.init(Data(manifestContent(toolsVersion: .none).utf8))).hexadecimalRepresentation
        let versionManifestChecksum = checksumAlgorithm
            .hash(.init(Data(manifestContent(toolsVersion: .v5_3).utf8))).hexadecimalRepresentation
        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        Fingerprint.ContentType.manifest(.none): Fingerprint(
                            origin: .registry(registryURL),
                            value: defaultManifestChecksum,
                            contentType: Fingerprint.ContentType.manifest(.none)
                        ),
                        Fingerprint.ContentType.manifest(.v5_3): Fingerprint(
                            origin: .registry(registryURL),
                            value: versionManifestChecksum,
                            contentType: Fingerprint.ContentType.manifest(.v5_3)
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            checksumAlgorithm: checksumAlgorithm
        )

        do {
            let manifest = try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: toolsVersion
            )
            let parsedToolsVersion = try ToolsVersionParser.parse(utf8String: manifest)
            #expect(parsedToolsVersion == expectedToolsVersion)
        }
    }

    @Test(arguments: [ToolsVersion.v5_3, nil])
    func getManifestContentWithNonMatchingChecksumInStorage_strict(toolsVersion: ToolsVersion?) async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first { $0.name == "swift-version" }
                .flatMap { ToolsVersion(string: $0.value!) } ?? ToolsVersion.current
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let data = Data(manifestContent(toolsVersion: toolsVersion).utf8)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        Fingerprint.ContentType.manifest(.none): Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: Fingerprint.ContentType.manifest(.none)
                        ),
                        Fingerprint.ContentType.manifest(.v5_3): Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: Fingerprint.ContentType.manifest(.v5_3)
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict, // intended for this test; don't change
            checksumAlgorithm: checksumAlgorithm
        )

        await #expect {
            try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: toolsVersion
            )
        } throws: { error in
            if case RegistryError.invalidChecksum = error {
                return true
            }
            return false
        }
    }

    @Test(arguments: [
        (toolsVersion: ToolsVersion.v5_3, expectedToolsVersion: ToolsVersion.v5_3),
        (toolsVersion: nil, expectedToolsVersion: ToolsVersion.current)
    ])
    func getManifestContentWithNonMatchingChecksumInStorage_warn(toolsVersion: ToolsVersion?, expectedToolsVersion: ToolsVersion) async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
            let toolsVersion = components.queryItems?.first { $0.name == "swift-version" }
                .flatMap { ToolsVersion(string: $0.value!) } ?? ToolsVersion.current
            // remove query
            components.query = nil
            let urlWithoutQuery = components.url
            switch (request.method, urlWithoutQuery) {
            case (.get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.get, manifestURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+swift")

                let data = Data(manifestContent(toolsVersion: toolsVersion).utf8)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "text/x-swift"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        Fingerprint.ContentType.manifest(.none): Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: Fingerprint.ContentType.manifest(.none)
                        ),
                        Fingerprint.ContentType.manifest(.v5_3): Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: Fingerprint.ContentType.manifest(.v5_3)
                        ),
                    ],
                ],
            ],
        ])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .warn, // intended for this test; don't change
            checksumAlgorithm: checksumAlgorithm
        )

        do {
            let observability = ObservabilitySystem.makeForTesting()
            // The checksum differs from that in storage, but error is not thrown
            // because fingerprintCheckingMode=.warn
            let manifest = try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: toolsVersion,
                observabilityScope: observability.topScope
            )

            // But there should be a warning
            try expectDiagnostics(observability.diagnostics) { result in
                result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
            }

            let parsedToolsVersion = try ToolsVersionParser.parse(utf8String: manifest)
            #expect(parsedToolsVersion == expectedToolsVersion)
        }
    }

    @Test func handles404() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: manifestURL,
            errorCode: 404,
            errorDescription: "not found"
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: nil
            )
        } throws: { error in
            if case RegistryError.failedRetrievingManifest(
                registry: configuration.defaultRegistry!,
                package: identity,
                version: version,
                error: RegistryError.packageVersionNotFound
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesServerError() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: manifestURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: nil
            )
        } throws: { error in
            if case RegistryError.failedRetrievingManifest(
                registry: configuration.defaultRegistry!,
                package: identity,
                version: version,
                error: RegistryError.serverError(
                    code: serverErrorHandler.errorCode,
                    details: serverErrorHandler.errorDescription
                )
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesRegistryNotAvailable() async throws {
        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.getManifestContent(
                package: identity,
                version: version,
                customToolsVersion: nil
            )
        } throws: { error in
            if case RegistryError.registryNotAvailable(registry) = error {
                return true
            }
            return false
        }
    }
}

@Suite("Download Source Archive") struct DownloadSourceArchive {
    @Test func downloadSourceArchive() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let author = UUID().uuidString
        let licenseURL = URL("https://github.com/\(identity.registry!.scope)/\(identity.registry!.name)/license")
        let readmeURL = URL("https://github.com/\(identity.registry!.scope)/\(identity.registry!.name)/readme")
        let repositoryURLs = [
            SourceControlURL("https://github.com/\(identity.registry!.scope)/\(identity.registry!.name)"),
            SourceControlURL("ssh://git@github.com:\(identity.registry!.scope)/\(identity.registry!.name).git"),
            SourceControlURL("git@github.com:\(identity.registry!.scope)/\(identity.registry!.name).git"),
        ]

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "\(author)"
                        },
                        "licenseURL": "\(licenseURL)",
                        "readmeURL": "\(readmeURL)",
                        "repositoryURLs": [\"\(repositoryURLs.map(\.absoluteString).joined(separator: "\", \""))\"]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(
                            name: "Content-Disposition",
                            value: "attachment; filename=\"\(identity)-\(version).zip\""
                        ),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: .none,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending(component: "package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending(component: "Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = try! AbsolutePath(validating: "/\(identity)-\(version)")

        try await registryClient.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path
        )

        let assert: (AbsolutePath) throws -> Void = { path in
            let contents = try fileSystem.getDirectoryContents(path)
            #expect(contents.sorted() == [RegistryReleaseMetadataStorage.fileName, "Package.swift"].sorted())

            let storedMetadata = try RegistryReleaseMetadataStorage.load(
                from: path.appending(component: RegistryReleaseMetadataStorage.fileName),
                fileSystem: fileSystem
            )
            #expect(storedMetadata.source == .registry(registryURL))
            #expect(storedMetadata.metadata.author?.name == author)
            #expect(storedMetadata.metadata.licenseURL == licenseURL)
            #expect(storedMetadata.metadata.readmeURL == readmeURL)
            #expect(storedMetadata.metadata.scmRepositoryURLs == repositoryURLs)
        }
        try assert(path)

        let syncPath = try! AbsolutePath(validating: "/\(identity)-\(version)-sync")
        try await withCheckedThrowingContinuation { continuation in
            registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                destinationPath: syncPath,
                progressHandler: nil,
                fileSystem: fileSystem,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }

        try assert(syncPath)
    }

    @Test func sourceArchiveMatchingChecksumInStorage() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        .sourceCode: Fingerprint(
                            origin: .registry(registryURL),
                            value: checksum,
                            contentType: .sourceCode
                        ),
                    ],
                ],
            ],
        ])
        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending("package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending("Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        try await registryClient.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path
        )

        let contents = try fileSystem.getDirectoryContents(path)
        #expect(contents.sorted() == [RegistryReleaseMetadataStorage.fileName, "Package.swift"].sorted())
    }

    @Test func sourceArchiveNonMatchingChecksumInStorage() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        .sourceCode: Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: .sourceCode
                        ),
                    ],
                ],
            ],
        ])
        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict, // intended for this test; don't change
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending("package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending("Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        await #expect {
            try await registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                fileSystem: fileSystem,
                destinationPath: path
            )
        } throws: { error in
            if case RegistryError.invalidChecksum = error {
                return true
            }
            return false
        }

        // download did not succeed so directory does not exist
        #expect(!fileSystem.exists(path))
    }

    @Test func sourceArchiveNonMatchingChecksumInStorage_fingerprintChecking_warn() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [
                        {
                            "name": "source-archive",
                            "type": "application/zip",
                            "checksum": "\(checksum)"
                        }
                    ],
                    "metadata": {
                        "author": {
                            "name": "J. Appleseed"
                        },
                        "licenseURL": "https://github.com/mona/LinkedList/license",
                        "readmeURL": "https://github.com/mona/LinkedList/readme",
                        "repositoryURLs": [
                            "https://github.com/mona/LinkedList",
                            "ssh://git@github.com:mona/LinkedList.git",
                            "git@github.com:mona/LinkedList.git"
                        ]
                    }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [
                    .registry: [
                        .sourceCode: Fingerprint(
                            origin: .registry(registryURL),
                            value: "non-matching checksum",
                            contentType: .sourceCode
                        ),
                    ],
                ],
            ],
        ])
        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .warn, // intended for this test; don't change
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending("package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending("Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")
        let observability = ObservabilitySystem.makeForTesting()

        // The checksum differs from that in storage, but error is not thrown
        // because fingerprintCheckingMode=.warn
        try await registryClient.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path,
            observabilityScope: observability.topScope
        )

        // But there should be a warning
        try expectDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }

        let contents = try fileSystem.getDirectoryContents(path)
        #expect(contents.sorted() == [RegistryReleaseMetadataStorage.fileName, "Package.swift"].sorted())
    }

    @Test func sourceArchiveChecksumNotInStorage() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        .init(name: "Content-Version", value: "1"),
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
                // `downloadSourceArchive` calls this API to fetch checksum
            case (.generic, .get, metadataURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

                let data = """
                {
                "id": "mona.LinkedList",
                "version": "1.1.1",
                "resources": [
                    {
                    "name": "source-archive",
                    "type": "application/zip",
                    "checksum": "\(checksum)"
                    }
                ],
                "metadata": {
                    "description": "One thing links to another."
                }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage()
        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending("package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending("Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        try await registryClient.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path
        )

        let contents = try fileSystem.getDirectoryContents(path)
        #expect(contents.sorted() == [RegistryReleaseMetadataStorage.fileName, "Package.swift"].sorted())

        // Expected checksum is not found in storage so the metadata API will be called
        let fingerprint = try fingerprintStorage.get(
            package: identity,
            version: version,
            kind: .registry,
            contentType: .sourceCode,
            observabilityScope: ObservabilitySystem
                .NOOP
        )
        #expect(SourceControlURL(registryURL) == fingerprint.origin.url)
        #expect(checksum == fingerprint.value)
    }

    @Test func downloadSourceArchiveOptionalContentVersion() async throws {
        let checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
        let checksum = checksumAlgorithm.hash(emptyZipFile).hexadecimalRepresentation

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.download(let fileSystem, let path), .get, downloadURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+zip")

                let data = Data(emptyZipFile.contents)
                try! fileSystem.writeFileContents(path, data: data)

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/zip"),
                        // Omit `Content-Version` header
                        .init(name: "Content-Disposition", value: #"attachment; filename="LinkedList-1.1.1.zip""#),
                        .init(
                            name: "Digest",
                            value: "sha-256=bc6c9a5d2f2226cfa1ef4fad8344b10e1cc2e82960f468f70d9ed696d26b3283"
                        ),
                    ]),
                    body: nil
                )
                // `downloadSourceArchive` calls this API to fetch checksum
            case (.generic, .get, metadataURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

                let data = """
                {
                "id": "mona.LinkedList",
                "version": "1.1.1",
                "resources": [
                    {
                    "name": "source-archive",
                    "type": "application/zip",
                    "checksum": "\(checksum)"
                    }
                ],
                "metadata": {
                    "description": "One thing links to another."
                }
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.security = .testDefault

        let fingerprintStorage = MockPackageFingerprintStorage()
        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            customArchiverProvider: { fileSystem in
                MockArchiver(handler: { _, from, to, callback in
                    let data = try fileSystem.readFileContents(from)
                    #expect(data == emptyZipFile)

                    let packagePath = to.appending("package")
                    try fileSystem.createDirectory(packagePath, recursive: true)
                    try fileSystem.writeFileContents(packagePath.appending("Package.swift"), string: "")
                    callback(.success(()))
                })
            },
            delegate: .none,
            checksumAlgorithm: checksumAlgorithm
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        try await registryClient.downloadSourceArchive(
            package: identity,
            version: version,
            fileSystem: fileSystem,
            destinationPath: path
        )

        let contents = try fileSystem.getDirectoryContents(path)
        // TODO: check metadata
        #expect(contents.sorted() == [RegistryReleaseMetadataStorage.fileName, "Package.swift"].sorted())
    }

    @Test func handles404() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: downloadURL,
            errorCode: 404,
            errorDescription: "not found"
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: .none,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            delegate: .none,
            checksumAlgorithm: MockHashAlgorithm()
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        await #expect {
            try await registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                fileSystem: fileSystem,
                destinationPath: path
            )
        } throws: { error in
            if case RegistryError
                .failedDownloadingSourceArchive(
                    registry: configuration.defaultRegistry!,
                    package: identity,
                    version: version,
                    error: RegistryError.packageVersionNotFound
                ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesServerError() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: downloadURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.kind, request.method, request.url) {
            case (.generic, .get, metadataURL):
                let data = """
                {
                    "id": "\(identity)",
                    "version": "\(version)",
                    "resources": [],
                    "metadata": {}
                }
                """.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                return try await serverErrorHandler.handle(request: request, progress: nil)
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: .none,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            delegate: .none,
            checksumAlgorithm: MockHashAlgorithm()
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        await #expect {
            try await registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                fileSystem: fileSystem,
                destinationPath: path
            )
        } throws: { error in
            if case RegistryError
                .failedDownloadingSourceArchive(
                    registry: configuration.defaultRegistry!,
                    package: identity,
                    version: version,
                    error: RegistryError.serverError(code: serverErrorHandler.errorCode, details: serverErrorHandler.errorDescription)
                ) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesRegistryNotAvailable() async throws {
        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let registryClient = RegistryClient(
            configuration: configuration,
            fingerprintStorage: .none,
            fingerprintCheckingMode: .strict,
            skipSignatureValidation: false,
            signingEntityStorage: .none,
            signingEntityCheckingMode: .strict,
            customHTTPClient: httpClient,
            delegate: .none,
            checksumAlgorithm: MockHashAlgorithm()
        )

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/LinkedList-1.1.1")

        await #expect {
            try await registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                fileSystem: fileSystem,
                destinationPath: path
            )
        } throws: { error in
            if case RegistryError.registryNotAvailable(registry) = error {
                return true
            }
            return false
        }
    }
}

@Suite("Lookup Identities") struct LookupIdentities {
    @Test func lookupIdentities() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, identifiersURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

                let data = #"""
                {
                    "identifiers": [
                    "mona.LinkedList"
                    ]
                }
                """#.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        let identities = try await registryClient.lookupIdentities(scmURL: packageURL)
        #expect([PackageIdentity.plain("mona.LinkedList")] == identities)

        let syncIdentities = try await withCheckedThrowingContinuation { continuation in
            registryClient.lookupIdentities(
                scmURL: packageURL,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
        #expect([PackageIdentity.plain("mona.LinkedList")] == syncIdentities)
    }

    @Test func notFound() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, identifiersURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
                return .notFound()
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        let identities = try await registryClient.lookupIdentities(scmURL: packageURL)
        #expect([] == identities)
    }

    @Test func handleServerError() async throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: identifiersURL,
            errorCode: Int.random(in: 405 ..< 500), // avoid 404 since it is not considered an error
            errorDescription: UUID().uuidString
        )

        let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
        await #expect {
            try await registryClient.lookupIdentities(scmURL: packageURL)
        } throws: { error in
            if case RegistryError.failedIdentityLookup(
                registry: configuration.defaultRegistry!,
                scmURL: packageURL,
                error: RegistryError.serverError(code: serverErrorHandler.errorCode, details: serverErrorHandler.errorDescription)
            ) = error {
                return true
            }
            return false
        }
    }

    @Test func requestAuthorization_token() async throws {
        let token = "top-sekret"

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, identifiersURL):
                #expect(request.headers.get("Authorization").first == "Bearer \(token)")
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

                let data = #"""
                {
                    "identifiers": [
                    "mona.LinkedList"
                    ]
                }
                """#.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.registryAuthentication[registryURL.host!] = .init(type: .token)

        let authorizationProvider = TestProvider(map: [registryURL.host!: ("token", token)])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            authorizationProvider: authorizationProvider
        )
        let identities = try await registryClient.lookupIdentities(scmURL: packageURL)
        #expect([PackageIdentity.plain("mona.LinkedList")] == identities)
    }

    @Test func requestAuthorization_basic() async throws {
        let user = "jappleseed"
        let password = "top-sekret"

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, identifiersURL):
                #expect(request.headers.get("Authorization").first == "Basic \(Data("\(user):\(password)".utf8).base64EncodedString())")
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")

                let data = #"""
                {
                    "identifiers": [
                    "mona.LinkedList"
                    ]
                }
                """#.data(using: .utf8)!

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Length", value: "\(data.count)"),
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: data
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.registryAuthentication[registryURL.host!] = .init(type: .basic)

        let authorizationProvider = TestProvider(map: [registryURL.host!: (user, password)])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            authorizationProvider: authorizationProvider
        )
        let identities = try await registryClient.lookupIdentities(scmURL: packageURL)
        #expect([PackageIdentity.plain("mona.LinkedList")] == identities)
    }
}

@Suite("Login") struct Login {
    @Test func login() async throws {
        let loginURL = URL("\(registryURL)/login")

        let token = "top-sekret"

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.post, loginURL):
                #expect(request.headers.get("Authorization").first == "Bearer \(token)")

                return .init(
                    statusCode: 200,
                    headers: .init([
                        .init(name: "Content-Version", value: "1"),
                    ])
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.registryAuthentication[registryURL.host!] = .init(type: .token)

        let authorizationProvider = TestProvider(map: [registryURL.host!: ("token", token)])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            authorizationProvider: authorizationProvider
        )
        try await registryClient.login(loginURL: loginURL)

        try await withCheckedThrowingContinuation { continuation in
            registryClient.login(
                loginURL: loginURL,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
    }

    @Test func handlesMissingCredentials() async throws {
        let loginURL = URL("\(registryURL)/login")

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.post, loginURL):
                #expect(request.headers.get("Authorization").first == nil)

                return .init(
                    statusCode: 401,
                    headers: .init([
                        .init(name: "Content-Version", value: "1"),
                    ])
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient
        )

        await #expect {
            try await registryClient.login(loginURL: loginURL)
        } throws: { error in
            if case RegistryError.loginFailed(_, _) = error {
                return true
            }
            return false
        }
    }

    @Test func handlesAuthenticationMethodNotSupported() async throws {
        let loginURL = URL("\(registryURL)/login")

        let token = "top-sekret"

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.post, loginURL):
                #expect(request.headers.get("Authorization").first != nil)

                return .init(
                    statusCode: 501,
                    headers: .init([
                        .init(name: "Content-Version", value: "1"),
                    ])
                )
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)
        configuration.registryAuthentication[registryURL.host!] = .init(type: .token)

        let authorizationProvider = TestProvider(map: [registryURL.host!: ("token", token)])

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            authorizationProvider: authorizationProvider
        )

        await #expect {
            try await registryClient.login(loginURL: loginURL)
        } throws: { error in
            if case RegistryError.loginFailed = error {
                return true
            }
            return false
        }
    }
}

@Suite("Registry Publishing") struct RegistryPublishing {
    @Test func publishSync() async throws {
        let expectedLocation =
        URL("https://\(registryURL)/packages\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")

        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.put, publishURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
                #expect(request.headers.get("X-Swift-Package-Signature-Format").first == nil)

                // TODO: implement multipart form parsing
                let body = String(decoding: request.body!, as: UTF8.self)
                XCTAssertMatch(body, .contains(archiveContent))
                XCTAssertMatch(body, .contains(metadataContent))

                return .init(
                    statusCode: 201,
                    headers: .init([
                        .init(name: "Location", value: expectedLocation.absoluteString),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: .none
                )
            default:
                throw StringError("method and url should match")
            }
        }

        try await withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending("\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)

            let result = try await withCheckedThrowingContinuation { continuation in
                return registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: .none,
                    metadataSignature: .none,
                    signatureFormat: .none,
                    fileSystem: localFileSystem,
                    observabilityScope: ObservabilitySystem.NOOP,
                    callbackQueue: .sharedConcurrent
                ) { result in continuation.resume(with: result) }
            }

            #expect(result == .published(expectedLocation))
        }
    }

    @Test func publishAsync() async throws {
        let expectedLocation =
        URL("https://\(registryURL)/status\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")
        let expectedRetry = Int.random(in: 10 ..< 100)

        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.put, publishURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
                #expect(request.headers.get("X-Swift-Package-Signature-Format").first == nil)

                // TODO: implement multipart form parsing
                let body = String(decoding: request.body!, as: UTF8.self)
                XCTAssertMatch(body, .contains(archiveContent))
                XCTAssertMatch(body, .contains(metadataContent))

                return .init(
                    statusCode: 202,
                    headers: .init([
                        .init(name: "Location", value: expectedLocation.absoluteString),
                        .init(name: "Retry-After", value: expectedRetry.description),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: .none
                )
            default:
                throw StringError("method and url should match")
            }
        }

        try await withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending("\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            let result = try await registryClient.publish(
                registryURL: registryURL,
                packageIdentity: identity,
                packageVersion: version,
                packageArchive: archivePath,
                packageMetadata: metadataPath,
                signature: .none,
                metadataSignature: .none,
                signatureFormat: .none,
                fileSystem: localFileSystem
            )

            #expect(result == .processing(statusURL: expectedLocation, retryAfter: expectedRetry))
        }
    }

    @Test func publishWithSignature() async throws {
        let expectedLocation =
        URL("https://\(registryURL)/packages\(identity.registry!.scope)/\(identity.registry!.name)/\(version)")

        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString
        let signature = UUID().uuidString
        let metadataSignature = UUID().uuidString
        let signatureFormat = SignatureFormat.cms_1_0_0

        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.put, publishURL):
                #expect(request.headers.get("Accept").first == "application/vnd.swift.registry.v1+json")
                #expect(request.headers.get("X-Swift-Package-Signature-Format").first == signatureFormat.rawValue)

                // TODO: implement multipart form parsing
                let body = String(decoding: request.body!, as: UTF8.self)
                XCTAssertMatch(body, .contains(archiveContent))
                XCTAssertMatch(body, .contains(metadataContent))
                XCTAssertMatch(body, .contains(signature))
                XCTAssertMatch(body, .contains(metadataSignature))

                return .init(
                    statusCode: 201,
                    headers: .init([
                        .init(name: "Location", value: expectedLocation.absoluteString),
                        .init(name: "Content-Version", value: "1"),
                    ]),
                    body: .none
                )
            default:
                throw StringError("method and url should match")
            }
        }

        try await withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending(component: "\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending(component: "\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            let result = try await registryClient.publish(
                registryURL: registryURL,
                packageIdentity: identity,
                packageVersion: version,
                packageArchive: archivePath,
                packageMetadata: metadataPath,
                signature: Array(signature.utf8),
                metadataSignature: Array(metadataSignature.utf8),
                signatureFormat: signatureFormat,
                fileSystem: localFileSystem
            )

            #expect(result == .published(expectedLocation))
        }
    }

    @Test func validateSignatureFormatIsRequiredIfSigned() throws {
        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString
        let signature = UUID().uuidString
        let metadataSignature = UUID().uuidString

        let handler: HTTPClient.Implementation = { _, _ in
            throw StringError("should not be called")
        }

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending(component: "\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending(component: "\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            await #expect {
                try await registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: Array(signature.utf8),
                    metadataSignature: Array(metadataSignature.utf8),
                    signatureFormat: .none,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError.missingSignatureFormat = error {
                    return true
                }
                return false
            }
        }
    }

    @Test func validateMetadataSignatureIsRequiredIfArchiveSigned() throws {
        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString
        let signature = UUID().uuidString
        let signatureFormat = SignatureFormat.cms_1_0_0

        let handler: HTTPClient.Implementation = { _, _ in
            throw StringError("should not be called")
        }

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending(component: "\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending(component: "\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            await #expect {
                try await registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: Array(signature.utf8),
                    metadataSignature: .none,
                    signatureFormat: signatureFormat,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError.invalidSignature = error {
                    return true
                }
                return false
            }
        }
    }

    @Test func validateArchiveSignatureIsRequiredIfMetadataSigned() throws {
        let archiveContent = UUID().uuidString
        let metadataContent = UUID().uuidString
        let metadataSignature = UUID().uuidString
        let signatureFormat = SignatureFormat.cms_1_0_0

        let handler: HTTPClient.Implementation = { _, _ in
            throw StringError("should not be called")
        }

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending(component: "\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, string: archiveContent)

            let metadataPath = temporaryDirectory.appending(component: "\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, string: metadataContent)

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            await #expect {
                try await registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: .none,
                    metadataSignature: Array(metadataSignature.utf8),
                    signatureFormat: signatureFormat,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError.invalidSignature = error {
                    return true
                }
                return false
            }
        }
    }

    @Test func handlesServerError() throws {
        let serverErrorHandler = ServerErrorHandler(
            method: .put,
            url: publishURL,
            errorCode: Int.random(in: 405 ..< 500),
            errorDescription: UUID().uuidString
        )

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, bytes: [])

            let metadataPath = temporaryDirectory.appending("\(identity)-\(version)-metadata.json")
            try localFileSystem.writeFileContents(metadataPath, bytes: [])

            let httpClient = HTTPClient(implementation: serverErrorHandler.handle)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            await #expect {
                try await registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: .none,
                    metadataSignature: .none,
                    signatureFormat: .none,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError
                    .failedPublishing(
                        RegistryError
                            .serverError(
                                code: serverErrorHandler.errorCode,
                                details: serverErrorHandler.errorDescription
                            )
                    ) = error {
                    return true
                }
                return false
            }
        }
    }

    @Test func handlesInvalidArchive() throws {
        let handler: HTTPClient.Implementation = { _, _ in
            throw StringError("should not be called")
        }

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("\(identity)-\(version).zip")
            // try localFileSystem.writeFileContents(archivePath, bytes: [])

            let metadataPath = temporaryDirectory.appending("\(identity)-\(version)-metadata.json")

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            await #expect {
                try await makeRegistryClient(configuration: configuration, httpClient: httpClient).publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: .none,
                    metadataSignature: .none,
                    signatureFormat: .none,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError.failedLoadingPackageArchive(archivePath) = error {
                    return true
                }
                return false
            }
        }
    }

    @Test func handlesInvalidMetadata() throws {
        let handler: HTTPClient.Implementation = { _, _ in
            throw StringError("should not be called")
        }

        try withTemporaryDirectory { temporaryDirectory in
            let archivePath = temporaryDirectory.appending("\(identity)-\(version).zip")
            try localFileSystem.writeFileContents(archivePath, bytes: [])

            let metadataPath = temporaryDirectory.appending("\(identity)-\(version)-metadata.json")

            let httpClient = HTTPClient(implementation: handler)
            var configuration = RegistryConfiguration()
            configuration.defaultRegistry = Registry(url: registryURL, supportsAvailability: false)

            let registryClient = makeRegistryClient(configuration: configuration, httpClient: httpClient)
            await #expect {
                try await registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: identity,
                    packageVersion: version,
                    packageArchive: archivePath,
                    packageMetadata: metadataPath,
                    signature: .none,
                    metadataSignature: .none,
                    signatureFormat: .none,
                    fileSystem: localFileSystem
                )
            } throws: { error in
                if case RegistryError.failedLoadingPackageMetadata(metadataPath) = error {
                    return true
                }
                return false
            }
        }
    }
}

@Suite("Registry Availablility") struct RegistryAvailability {
    @Test func checkAvailability() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, availabilityURL):
                return .okay()
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        let registry = Registry(url: registryURL, supportsAvailability: true)

        let registryClient = makeRegistryClient(
            configuration: .init(),
            httpClient: httpClient
        )

        let status = try await registryClient.checkAvailability(registry: registry)
        #expect(status == .available)

        let syncStatus = try await withCheckedThrowingContinuation { continuation in
            registryClient.checkAvailability(
                registry: registry,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: { continuation.resume(with: $0) }
            )
        }
        #expect(syncStatus == .available)
    }

    @Test func handleNotAvailable() async throws {
        for unavailableStatus in RegistryClient.AvailabilityStatus.unavailableStatusCodes {
            let handler: HTTPClient.Implementation = { request, _ in
                switch (request.method, request.url) {
                case (.get, availabilityURL):
                    return .init(statusCode: unavailableStatus)
                default:
                    throw StringError("method and url should match")
                }
            }

            let httpClient = HTTPClient(implementation: handler)
            let registry = Registry(url: registryURL, supportsAvailability: true)

            let registryClient = makeRegistryClient(
                configuration: .init(),
                httpClient: httpClient
            )

            let status = try await registryClient.checkAvailability(registry: registry)
            #expect(status == .unavailable)
        }
    }

    @Test func handleServerError() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, availabilityURL):
                return .serverError(reason: "boom")
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        let registry = Registry(url: registryURL, supportsAvailability: true)

        let registryClient = makeRegistryClient(
            configuration: .init(),
            httpClient: httpClient
        )

        let status = try await registryClient.checkAvailability(registry: registry)
        #expect(status == .error("unknown server error (500)"))
    }

    @Test func handleMethodNotSupported() async throws {
        let handler: HTTPClient.Implementation = { request, _ in
            switch (request.method, request.url) {
            case (.get, availabilityURL):
                return .serverError(reason: "boom")
            default:
                throw StringError("method and url should match")
            }
        }

        let httpClient = HTTPClient(implementation: handler)
        let registry = Registry(url: registryURL, supportsAvailability: false)

        let registryClient = makeRegistryClient(
            configuration: .init(),
            httpClient: httpClient
        )

        await XCTAssertAsyncThrowsError(try await registryClient.checkAvailability(registry: registry)) { error in
            #expect(error as? StringError == StringError("registry \(registry.url) does not support availability checks."))
        }
    }
}

// MARK: - Sugar

extension RegistryClient {
    fileprivate func getPackageMetadata(package: PackageIdentity) async throws -> RegistryClient.PackageMetadata {
        try await self.getPackageMetadata(
            package: package,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    func getPackageVersionMetadata(
        package: PackageIdentity,
        version: Version
    ) async throws -> PackageVersionMetadata {
        try await self.getPackageVersionMetadata(
            package: package,
            version: version,
            fileSystem: InMemoryFileSystem(),
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    func getPackageVersionMetadata(
        package: PackageIdentity.RegistryIdentity,
        version: Version
    ) async throws -> PackageVersionMetadata {
        return try await self.getPackageVersionMetadata(
            package: package.underlying,
            version: version,
            fileSystem: InMemoryFileSystem(),
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        observabilityScope: ObservabilityScope = ObservabilitySystem.NOOP
    ) async throws {
        try await self.downloadSourceArchive(
            package: package,
            version: version,
            destinationPath: destinationPath,
            progressHandler: .none,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }

    fileprivate func lookupIdentities(scmURL: SourceControlURL) async throws -> Set<PackageIdentity> {
        try await self.lookupIdentities(
            scmURL: scmURL,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?
    ) async throws -> String {
        try await self.getManifestContent(
            package: package,
            version: version,
            customToolsVersion: customToolsVersion,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    fileprivate func login(loginURL: URL) async throws {
        try await self.login(
            loginURL: loginURL,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    func publish(
        registryURL: URL,
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageArchive: AbsolutePath,
        packageMetadata: AbsolutePath?,
        signature: [UInt8]?,
        metadataSignature: [UInt8]?,
        signatureFormat: SignatureFormat?,
        fileSystem: FileSystem
    ) async throws -> RegistryClient.PublishResult {
        try await self.publish(
            registryURL: registryURL,
            packageIdentity: packageIdentity,
            packageVersion: packageVersion,
            packageArchive: packageArchive,
            packageMetadata: packageMetadata,
            signature: signature,
            metadataSignature: metadataSignature,
            signatureFormat: signatureFormat,
            fileSystem: fileSystem,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }

    func checkAvailability(registry: Registry) async throws -> AvailabilityStatus {
        try await self.checkAvailability(
            registry: registry,
            observabilityScope: ObservabilitySystem.NOOP
        )
    }
}

func makeRegistryClient(
    configuration: RegistryConfiguration,
    httpClient: HTTPClient,
    authorizationProvider: AuthorizationProvider? = .none,
    fingerprintStorage: PackageFingerprintStorage = MockPackageFingerprintStorage(),
    fingerprintCheckingMode: FingerprintCheckingMode = .strict,
    skipSignatureValidation: Bool = false,
    signingEntityStorage: PackageSigningEntityStorage = MockPackageSigningEntityStorage(),
    signingEntityCheckingMode: SigningEntityCheckingMode = .strict,
    checksumAlgorithm: HashAlgorithm = MockHashAlgorithm()
) -> RegistryClient {
    RegistryClient(
        configuration: configuration,
        fingerprintStorage: fingerprintStorage,
        fingerprintCheckingMode: fingerprintCheckingMode,
        skipSignatureValidation: skipSignatureValidation,
        signingEntityStorage: signingEntityStorage,
        signingEntityCheckingMode: signingEntityCheckingMode,
        authorizationProvider: authorizationProvider,
        customHTTPClient: httpClient,
        customArchiverProvider: { _ in MockArchiver() },
        delegate: .none,
        checksumAlgorithm: checksumAlgorithm
    )
}

private struct TestProvider: AuthorizationProvider {
    let map: [String: (user: String, password: String)]

    func authentication(for url: URL) -> (user: String, password: String)? {
        self.map[url.host!]
    }
}

struct ServerErrorHandler {
    let method: HTTPMethod
    let url: URL
    let errorCode: Int
    let errorDescription: String

    init(
        method: HTTPMethod,
        url: URL,
        errorCode: Int,
        errorDescription: String
    ) {
        self.method = method
        self.url = url
        self.errorCode = errorCode
        self.errorDescription = errorDescription
    }

    @Sendable func handle(
        request: HTTPClient.Request,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClient.Response {
        let data = """
        {
            "detail": "\(self.errorDescription)"
        }
        """.data(using: .utf8)!

        if request.method == self.method &&
            request.url == self.url
        {
            return .init(
                statusCode: self.errorCode,
                headers: .init([
                    .init(name: "Content-Length", value: "\(data.count)"),
                    .init(name: "Content-Type", value: "application/problem+json"),
                    .init(name: "Content-Version", value: "1"),
                ]),
                body: data
            )
        } else {
            throw StringError("unexpected request")
        }
    }
}

struct UnavailableServerErrorHandler {
    let registryURL: URL
    init(registryURL: URL) {
        self.registryURL = registryURL
    }

    @Sendable func handle(
        request: HTTPClient.Request,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClient.Response {
        if request.method == .get && request.url == URL("\(self.registryURL)/availability") {
            return .init(
                statusCode: RegistryClient.AvailabilityStatus.unavailableStatusCodes.first!
            )
        } else {
            throw StringError("unexpected request")
        }
    }
}

private func manifestContent(toolsVersion: ToolsVersion?) -> String {
    """
    // swift-tools-version:\(toolsVersion ?? ToolsVersion.current)

    import PackageDescription

    let package = Package()
    """
}
