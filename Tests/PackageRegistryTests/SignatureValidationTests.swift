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
import PackageModel
@testable import PackageRegistry
import PackageSigning
import SPMTestSupport
import TSCBasic
import XCTest

import struct TSCUtility.Version

final class SignatureValidationTests: XCTestCase {
    // TODO: add testUnsignedPackage_shouldPrompt
    // TODO: add tests for signed package

    func testUnsignedPackage_shouldError() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Get metadata endpoint will be called to see if package version is signed
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

        var signingConfiguration = RegistryConfiguration.Security.Signing()
        signingConfiguration.onUnsigned = .error // intended for this test; don't change
        configuration.security = RegistryConfiguration.Security(
            default: RegistryConfiguration.Security.Global(
                signing: signingConfiguration
            )
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let signatureValidation = SignatureValidation(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode,
            versionMetadataProvider: registryClient.getPackageVersionMetadata,
            delegate: RejectingSignatureValidationDelegate()
        )

        // Package is not signed. With onUnsigned = .error,
        // an error gets thrown.
        XCTAssertThrowsError(
            try signatureValidation.validate(
                registry: registry,
                package: package,
                version: version,
                content: Data(emptyZipFile.contents),
                configuration: configuration.signing(for: package, registry: registry)
            )
        ) { error in
            guard case RegistryError.sourceArchiveNotSigned = error else {
                return XCTFail("Expected RegistryError.sourceArchiveNotSigned, got '\(error)'")
            }
        }
    }

    func testUnsignedPackage_shouldWarn() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Get metadata endpoint will be called to see if package version is signed
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

        var signingConfiguration = RegistryConfiguration.Security.Signing()
        signingConfiguration.onUnsigned = .warn // intended for this test; don't change
        configuration.security = RegistryConfiguration.Security(
            default: RegistryConfiguration.Security.Global(
                signing: signingConfiguration
            )
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let signatureValidation = SignatureValidation(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode,
            versionMetadataProvider: registryClient.getPackageVersionMetadata,
            delegate: RejectingSignatureValidationDelegate()
        )

        let observability = ObservabilitySystem.makeForTesting()

        // Package is not signed. With onUnsigned = .warn,
        // no error gets thrown but there should be a warning
        XCTAssertNoThrow(
            try signatureValidation.validate(
                registry: registry,
                package: package,
                version: version,
                content: Data(emptyZipFile.contents),
                configuration: configuration.signing(for: package, registry: registry),
                observabilityScope: observability.topScope
            )
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("is not signed"), severity: .warning)
        }
    }

    func testUnsignedPackage_shouldPrompt() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")
        let checksum = "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"

        // Get metadata endpoint will be called to see if package version is signed
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

        var signingConfiguration = RegistryConfiguration.Security.Signing()
        signingConfiguration.onUnsigned = .prompt // intended for this test; don't change
        configuration.security = RegistryConfiguration.Security(
            default: RegistryConfiguration.Security.Global(
                signing: signingConfiguration
            )
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        // prompt returning false
        do {
            let signatureValidation = SignatureValidation(
                signingEntityStorage: signingEntityStorage,
                signingEntityCheckingMode: signingEntityCheckingMode,
                versionMetadataProvider: registryClient.getPackageVersionMetadata,
                delegate: RejectingSignatureValidationDelegate()
            )

            // Package is not signed. With onUnsigned = .error,
            // an error gets thrown.
            XCTAssertThrowsError(
                try signatureValidation.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    content: Data(emptyZipFile.contents),
                    configuration: configuration.signing(for: package, registry: registry)
                )
            ) { error in
                guard case RegistryError.sourceArchiveNotSigned = error else {
                    return XCTFail("Expected RegistryError.sourceArchiveNotSigned, got '\(error)'")

                }
            }
        }

        // prompt returning continue
        do {
            let signatureValidation = SignatureValidation(
                signingEntityStorage: signingEntityStorage,
                signingEntityCheckingMode: signingEntityCheckingMode,
                versionMetadataProvider: registryClient.getPackageVersionMetadata,
                delegate: AcceptingSignatureValidationDelegate()
            )

            // Package is not signed, signingEntity should be nil
            let signingEntity = try signatureValidation.validate(
                registry: registry,
                package: package,
                version: version,
                content: Data(emptyZipFile.contents),
                configuration: configuration.signing(for: package, registry: registry)
            )
            XCTAssertNil(signingEntity)
        }
    }

    func testFailedToFetchSignature_shouldError() throws {
        let registryURL = URL("https://packages.example.com")
        let identity = PackageIdentity.plain("mona.LinkedList")
        let package = identity.registry!
        let version = Version("1.1.1")
        let metadataURL = URL("\(registryURL)/\(package.scope)/\(package.name)/\(version)")

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

        var signingConfiguration = RegistryConfiguration.Security.Signing()
        signingConfiguration.onUnsigned = .error // intended for this test; don't change
        configuration.security = RegistryConfiguration.Security(
            default: RegistryConfiguration.Security.Global(
                signing: signingConfiguration
            )
        )

        let signingEntityStorage = MockPackageSigningEntityStorage()
        let signingEntityCheckingMode = SigningEntityCheckingMode.strict

        let registryClient = makeRegistryClient(
            configuration: configuration,
            httpClient: httpClient,
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )

        let signatureValidation = SignatureValidation(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode,
            versionMetadataProvider: registryClient.getPackageVersionMetadata,
            delegate: RejectingSignatureValidationDelegate()
        )

        // Failed to fetch package metadata / signature
        XCTAssertThrowsError(
            try signatureValidation.validate(
                registry: registry,
                package: package,
                version: version,
                content: Data(emptyZipFile.contents),
                configuration: configuration.signing(for: package, registry: registry)
            )
        ) { error in
            guard case RegistryError.failedRetrievingSourceArchiveSignature = error else {
                return XCTFail("Expected RegistryError.failedRetrievingSourceArchiveSignature, got '\(error)'")
            }
        }
    }
}

extension SignatureValidation {
    fileprivate func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        observabilityScope: ObservabilityScope? = nil
    ) throws -> SigningEntity? {
        try tsc_await {
            self.validate(
                registry: registry,
                package: package,
                version: version,
                content: content,
                configuration: configuration,
                timeout: nil,
                observabilityScope: observabilityScope ?? ObservabilitySystem.NOOP,
                callbackQueue: .sharedConcurrent,
                completion: $0
            )
        }
    }
}

fileprivate struct RejectingSignatureValidationDelegate: SignatureValidation.Delegate {
    func onUnsigned(registry: PackageRegistry.Registry, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        completion(false)
    }

    func onUntrusted(registry: PackageRegistry.Registry, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        completion(false)
    }
}

fileprivate struct AcceptingSignatureValidationDelegate: SignatureValidation.Delegate {
    func onUnsigned(registry: PackageRegistry.Registry, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        completion(true)
    }

    func onUntrusted(registry: PackageRegistry.Registry, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        completion(true)
    }
}
