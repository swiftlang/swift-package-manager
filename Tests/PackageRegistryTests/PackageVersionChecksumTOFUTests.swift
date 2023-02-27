//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageFingerprint
import PackageModel
@testable import PackageRegistry
import SPMTestSupport
import TSCBasic
import XCTest

import struct TSCUtility.Version

final class PackageVersionChecksumTOFUTests: XCTestCase {
    func testChecksumSeenForTheFirstTime() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Get package version metadata endpoint will be called to fetch expected checksum
        let handler: LegacyHTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

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

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // Checksum for package version not found in storage,
        // so we fetch metadata to get the expected checksum,
        // then save it to storage for future reference.
        XCTAssertNoThrow(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        )

        // Checksum should have been saved to storage
        let fingerprint = try tsc_await { callback in
            fingerprintStorage.get(
                package: identity,
                version: version,
                kind: .registry,
                observabilityScope: ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                callback: callback
            )
        }
        XCTAssertEqual(registryURL, fingerprint.origin.url)
        XCTAssertEqual(checksum, fingerprint.value)
    }

    func testMetadataChecksumConflictsWithStorage_strictMode() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        let handler: LegacyHTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

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

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = WriteConflictFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.strict // intended for this test, don't change

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // We get expected checksum from metadata but it's different
        // from value in storage, and because of .strict mode,
        // an error is thrown.
        XCTAssertThrowsError(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        ) { error in
            guard case RegistryError.checksumChanged = error else {
                return XCTFail("Expected RegistryError.checksumChanged, got '\(error)'")
            }
        }
    }

    func testMetadataChecksumConflictsWithStorage_warnMode() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        let handler: LegacyHTTPClient.Handler = { request, _, completion in
            switch (request.method, request.url) {
            case (.get, metadataURL):
                XCTAssertEqual(request.headers.get("Accept").first, "application/vnd.swift.registry.v1+json")

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

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = WriteConflictFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.warn // intended for this test, don't change

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        let observability = ObservabilitySystem.makeForTesting()

        // We get expected checksum from metadata and it's different
        // from value in storage, but because of .warn mode,
        // no error is thrown.
        XCTAssertNoThrow(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }
    }

    func testFetchMetadataChecksum_404() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: metadataURL,
            errorCode: 404,
            errorDescription: "not found"
        )

        let httpClient = LegacyHTTPClient(handler: serverErrorHandler.handle)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // We get expected checksum from metadata but it's different
        // from value in storage, and because of .strict mode,
        // an error is thrown.
        XCTAssertThrowsError(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        ) { error in
            guard case RegistryError.failedRetrievingReleaseChecksum = error else {
                return XCTFail("Expected RegistryError.failedRetrievingReleaseChecksum, got '\(error)'")
            }
        }
    }

    func testFetchMetadataChecksum_ServerError() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        let serverErrorHandler = ServerErrorHandler(
            method: .get,
            url: metadataURL,
            errorCode: 500,
            errorDescription: UUID().uuidString
        )

        let httpClient = LegacyHTTPClient(handler: serverErrorHandler.handle)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // We get expected checksum from metadata but it's different
        // from value in storage, and because of .strict mode,
        // an error is thrown.
        XCTAssertThrowsError(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        ) { error in
            guard case RegistryError.failedRetrievingReleaseChecksum = error else {
                return XCTFail("Expected RegistryError.failedRetrievingReleaseChecksum, got '\(error)'")
            }
        }
    }

    func testFetchMetadataChecksum_RegistryNotAvailable() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        let serverErrorHandler = UnavailableServerErrorHandler(registryURL: registryURL)

        let httpClient = LegacyHTTPClient(handler: serverErrorHandler.handle)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: true)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage()
        let fingerprintCheckingMode = FingerprintCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // We get expected checksum from metadata but it's different
        // from value in storage, and because of .strict mode,
        // an error is thrown.
        XCTAssertThrowsError(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        ) { error in
            guard case RegistryError.failedRetrievingReleaseChecksum = error else {
                return XCTFail("Expected RegistryError.failedRetrievingReleaseChecksum, got '\(error)'")
            }
        }
    }

    func testChecksumMatchingStorage() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Checksum already exists in storage so API will not be called
        let handler: LegacyHTTPClient.Handler = { _, _, completion in
            completion(.failure(StringError("Unexpected request")))
        }

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [.registry: Fingerprint(origin: .registry(registryURL), value: checksum)],
            ],
        ])
        let fingerprintCheckingMode = FingerprintCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // Checksum for package version found in storage,
        // so we just compare that with the given checksum.
        XCTAssertNoThrow(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        )
    }

    func testChecksumDoesNotMatchExpectedFromStorage_strictMode() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Checksum already exists in storage so API will not be called
        let handler: LegacyHTTPClient.Handler = { _, _, completion in
            completion(.failure(StringError("Unexpected request")))
        }

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [.registry: Fingerprint(origin: .registry(registryURL), value: "non-matching checksum")],
            ],
        ])
        let fingerprintCheckingMode = FingerprintCheckingMode.strict // intended for this test; don't change

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        // Checksum for package version found in storage,
        // so we just compare that with the given checksum.
        // Since the checksums don't match, and because of
        // .strict mode, an error is thrown.
        XCTAssertThrowsError(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum
            )
        ) { error in
            guard case RegistryError.invalidChecksum = error else {
                return XCTFail("Expected RegistryError.invalidChecksum, got '\(error)'")
            }
        }
    }

    func testChecksumDoesNotMatchExpectedFromStorage_warnMode() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Checksum already exists in storage so API will not be called
        let handler: LegacyHTTPClient.Handler = { _, _, completion in
            completion(.failure(StringError("Unexpected request")))
        }

        let httpClient = LegacyHTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none

        let registry = Registry(url: registryURL, supportsAvailability: false)
        var configuration = RegistryConfiguration()
        configuration.defaultRegistry = registry

        let fingerprintStorage = MockPackageFingerprintStorage([
            identity: [
                version: [.registry: Fingerprint(origin: .registry(registryURL), value: "non-matching checksum")],
            ],
        ])
        let fingerprintCheckingMode = FingerprintCheckingMode.warn // intended for this test; don't change

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode
        )

        let tofu = PackageVersionChecksumTOFU(
            fingerprintStorage: fingerprintStorage,
            fingerprintCheckingMode: fingerprintCheckingMode,
            registryClient: registryClient
        )

        let observability = ObservabilitySystem.makeForTesting()

        // Checksum for package version found in storage,
        // so we just compare that with the given checksum.
        // The checksums don't match, but because of
        // .warn mode, no error is thrown.
        XCTAssertNoThrow(
            try tofu.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                observabilityScope: observability.topScope
            )
        )

        // But there should be a warning
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("does not match previously recorded value"), severity: .warning)
        }
    }
}

extension PackageVersionChecksumTOFU {
    fileprivate func check(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        checksum: String,
        observabilityScope: ObservabilityScope? = nil
    ) throws {
        try tsc_await {
            self.check(
                registry: registry,
                package: package,
                version: version,
                checksum: checksum,
                timeout: nil,
                observabilityScope: observabilityScope ?? ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }
}

private class WriteConflictFingerprintStorage: PackageFingerprintStorage {
    func get(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void
    ) {
        callback(.failure(PackageFingerprintStorageError.notFound))
    }

    func put(
        package: PackageIdentity,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        let existing = Fingerprint(origin: fingerprint.origin, value: "xxx-\(fingerprint.value)")
        callback(.failure(PackageFingerprintStorageError.conflict(given: fingerprint, existing: existing)))
    }

    func get(
        package: PackageReference,
        version: Version,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<[Fingerprint.Kind: Fingerprint], Error>) -> Void
    ) {
        self.get(
            package: package.identity,
            version: version,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    func put(
        package: PackageReference,
        version: Version,
        fingerprint: Fingerprint,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.put(
            package: package.identity,
            version: version,
            fingerprint: fingerprint,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            callback: callback
        )
    }
}
