//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import PackageFingerprint
import PackageLoading
import PackageModel
import PackageSigning

import protocol TSCBasic.HashAlgorithm

import struct TSCUtility.Version

public protocol RegistryClientDelegate {
    func onUnsigned(registry: Registry, package: PackageIdentity, version: Version) async -> Bool
    func onUntrusted(registry: Registry, package: PackageIdentity, version: Version) async -> Bool
}

/// Package registry client.
/// API specification: https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md
public final class RegistryClient: Cancellable {
    public typealias Delegate = RegistryClientDelegate

    private static let apiVersion: APIVersion = .v1
    private static let availabilityCacheTTL: DispatchTimeInterval = .seconds(5 * 60)
    private static let metadataCacheTTL: DispatchTimeInterval = .seconds(60 * 60)

    private var configuration: RegistryConfiguration
    private let archiverProvider: (FileSystem) -> Archiver
    private let httpClient: HTTPClient
    private let authorizationProvider: HTTPClientConfiguration.AuthorizationProvider?
    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode
    private let skipSignatureValidation: Bool
    private let signingEntityStorage: PackageSigningEntityStorage?
    private let signingEntityCheckingMode: SigningEntityCheckingMode
    private let jsonDecoder: JSONDecoder
    private let delegate: Delegate?
    private let checksumAlgorithm: HashAlgorithm

    private let availabilityCache = ThreadSafeKeyValueStore<
        URL,
        (status: Result<AvailabilityStatus, Error>, expires: DispatchTime)
    >()

    private let metadataCache = ThreadSafeKeyValueStore<
        MetadataCacheKey,
        (metadata: Serialization.VersionMetadata, expires: DispatchTime)
    >()

    public init(
        configuration: RegistryConfiguration,
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        skipSignatureValidation: Bool,
        signingEntityStorage: PackageSigningEntityStorage?,
        signingEntityCheckingMode: SigningEntityCheckingMode,
        authorizationProvider: AuthorizationProvider? = .none,
        customHTTPClient: HTTPClient? = .none,
        customArchiverProvider: ((FileSystem) -> Archiver)? = .none,
        delegate: Delegate?,
        checksumAlgorithm: HashAlgorithm
    ) {
        self.configuration = configuration

        if let authorizationProvider {
            self.authorizationProvider = { url in
                guard let registryAuthentication = try? configuration.authentication(for: url) else {
                    return .none
                }
                guard let (user, password) = authorizationProvider.authentication(for: url) else {
                    return .none
                }

                switch registryAuthentication.type {
                case .basic:
                    let authorizationString = "\(user):\(password)"
                    let authorizationData = Data(authorizationString.utf8)
                    return "Basic \(authorizationData.base64EncodedString())"
                case .token: // `user` value is irrelevant in this case
                    return "Bearer \(password)"
                }
            }
        } else {
            self.authorizationProvider = .none
        }

        self.httpClient = customHTTPClient ?? HTTPClient()
        self.archiverProvider = customArchiverProvider ?? { fileSystem in ZipArchiver(fileSystem: fileSystem) }
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.skipSignatureValidation = skipSignatureValidation
        self.signingEntityStorage = signingEntityStorage
        self.signingEntityCheckingMode = signingEntityCheckingMode
        self.jsonDecoder = JSONDecoder.makeWithDefaults()
        self.delegate = delegate
        self.checksumAlgorithm = checksumAlgorithm
    }

    public var explicitlyConfigured: Bool {
        self.configuration.explicitlyConfigured
    }

    // not thread safe
    // marked public for cross module visibility
    public var defaultRegistry: Registry? {
        get {
            self.configuration.defaultRegistry
        }
        set {
            self.configuration.defaultRegistry = newValue
        }
    }

    /// Cancel any outstanding requests
    public func cancel(deadline: DispatchTime) throws {
        // FIXME:
//        try self.httpClient.cancel(deadline: deadline)
    }

    public func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) async throws {
        try await self.signingEntityStorage?.changeSigningEntityFromVersion(
            package: package,
            version: version,
            signingEntity: signingEntity,
            origin: origin,
            observabilityScope: observabilityScope
        )
    }

    public func getPackageMetadata(
        package: PackageIdentity,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws -> PackageMetadata {
        guard let registryIdentity = package.registry else {
            throw RegistryError.invalidPackageIdentity(package)
        }

        guard let registry = self.configuration.registry(for: registryIdentity.scope) else {
            throw RegistryError.registryNotConfigured(scope: registryIdentity.scope)
        }

        observabilityScope.emit(debug: "registry for \(package): \(registry)")

        if registry.supportsAvailability {
            try await checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }

        return try await self._getPackageMetadata(
            registry: registry,
            package: registryIdentity,
            timeout: timeout,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _getPackageMetadata(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) async throws -> PackageMetadata {
        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents("\(package.scope)", "\(package.name)")
        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }
        
        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout)
        )
        
        let start = DispatchTime.now()
        observabilityScope.emit(info: "retrieving \(package) metadata from \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)

            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                let packageMetadata = try response.parseJSON(
                    Serialization.PackageMetadata.self,
                    decoder: self.jsonDecoder
                )
                
                let versions = packageMetadata.releases.filter { $0.value.problem == nil }
                    .compactMap { Version($0.key) }
                    .sorted(by: >)
                
                let alternateLocations = try response.headers.parseAlternativeLocationLinks()
                
                return PackageMetadata(
                    registry: registry,
                    versions: versions,
                    alternateLocations: alternateLocations?.map(\.url)
                )
            case 404:
                throw RegistryError.packageNotFound
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
            }
        } catch {
            throw RegistryError.failedRetrievingReleases(registry: registry, package: package.underlying, error: error)
        }
    }

    public func getPackageVersionMetadata(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval? = .none,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> PackageVersionMetadata {
        guard let registryIdentity = package.registry else {
            throw RegistryError.invalidPackageIdentity(package)
        }

        guard let registry = self.configuration.registry(for: registryIdentity.scope) else {
            throw RegistryError.registryNotConfigured(scope: registryIdentity.scope)
        }

        if registry.supportsAvailability {
            try await self.checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }
        return try await self._getPackageVersionMetadata(
            registry: registry,
            package: registryIdentity,
            version: version,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _getPackageVersionMetadata(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> PackageVersionMetadata {
        let versionMetadata = try await self._getRawPackageVersionMetadata(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            completion(
                result.tryMap { versionMetadata in
                    PackageVersionMetadata(
                        registry: registry,
                        licenseURL: versionMetadata.metadata?.licenseURL.flatMap { URL(string: $0) },
                        readmeURL: versionMetadata.metadata?.readmeURL.flatMap { URL(string: $0) },
                        repositoryURLs: versionMetadata.metadata?.repositoryURLs?.compactMap { SourceControlURL($0) },
                        resources: versionMetadata.resources.map {
                            .init(
                                name: $0.name,
                                type: $0.type,
                                checksum: $0.checksum,
                                signing: $0.signing.flatMap {
                                    PackageVersionMetadata.Signing(
                                        signatureBase64Encoded: $0.signatureBase64Encoded,
                                        signatureFormat: $0.signatureFormat
                                    )
                                },
                                signingEntity: $0.signing.flatMap {
                                    guard let signatureData = Data(base64Encoded: $0.signatureBase64Encoded) else {
                                        return nil
                                    }
                                    guard let signatureFormat = SignatureFormat(rawValue: $0.signatureFormat) else {
                                        return nil
                                    }
                                    let configuration = self.configuration.signing(for: package, registry: registry)
                                    return try? temp_await { completion in
                                        let wrappedCompletion: @Sendable (Result<SigningEntity?, Error>) -> Void = {
                                            completion($0)
                                        }

        let resources = await withTaskGroup(of: PackageVersionMetadata.Resource?.self) { group in
            for resource in versionMetadata.resources {
                group.addTask {
                    .init(
                        name: resource.name,
                        type: resource.type,
                        checksum: resource.checksum,
                        signing: resource.signing.flatMap {
                            PackageVersionMetadata.Signing(
                                signatureBase64Encoded: $0.signatureBase64Encoded,
                                signatureFormat: $0.signatureFormat
                            )
                        },
                        signingEntity: await self.getPackageVersionMetadataSigningEntity(
                            signing: resource.signing,
                            registry: registry,
                            package: package,
                            fileSystem: fileSystem
                        )
                    )
                }
            }

            var results = [PackageVersionMetadata.Resource]()
            for await case let result? in group {
                results.append(result)
            }

            return results
        }

        return PackageVersionMetadata(
            registry: registry,
            licenseURL: versionMetadata.metadata?.licenseURL.flatMap { URL(string: $0) },
            readmeURL: versionMetadata.metadata?.readmeURL.flatMap { URL(string: $0) },
            repositoryURLs: versionMetadata.metadata?.repositoryURLs?.compactMap { URL(string: $0) },
            resources: resources,
            author: versionMetadata.metadata?.author.map {
                .init(
                    name: $0.name,
                    email: $0.email,
                    description: $0.description,
                    organization: $0.organization.map {
                        .init(
                            name: $0.name,
                            email: $0.email,
                            description: $0.description,
                            url: $0.url.flatMap { URL(string: $0) }
                        )
                    },
                    url: $0.url.flatMap { URL(string: $0) }
                )
            },
            description: versionMetadata.metadata?.description,
            publishedAt: versionMetadata.metadata?.originalPublicationTime ?? versionMetadata.publishedAt
        )
    }

    private func getPackageVersionMetadataSigningEntity(
        signing: Serialization.VersionMetadata.Signing?,
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        fileSystem: FileSystem
    ) async -> SigningEntity? {
        guard let signing else {
            return nil
        }

        guard let signatureData = Data(base64Encoded: signing.signatureBase64Encoded) else {
            return nil
        }
        guard let signatureFormat = SignatureFormat(rawValue: signing.signatureFormat) else {
            return nil
        }
        let configuration = self.configuration.signing(for: package, registry: registry)
        return try? await SignatureValidation.extractSigningEntity(
            signature: [UInt8](signatureData),
            signatureFormat: signatureFormat,
            configuration: configuration,
            fileSystem: fileSystem
        )
    }

    private func _getRawPackageVersionMetadata(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) async throws -> Serialization.VersionMetadata {
        let cacheKey = MetadataCacheKey(registry: registry, package: package)
        if let cached = self.metadataCache[cacheKey], cached.expires < .now() {
            return cached.metadata
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents("\(package.scope)", "\(package.name)", "\(version)")

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout)
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "retrieving \(package) \(version) metadata from \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)
            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                let metadata = try response.parseJSON(
                    Serialization.VersionMetadata.self,
                    decoder: self.jsonDecoder
                )
                self.metadataCache[cacheKey] = (metadata: metadata, expires: .now() + Self.metadataCacheTTL)
                return metadata
            case 404:
                throw RegistryError.packageVersionNotFound
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
            }
        } catch {
            throw RegistryError.failedRetrievingReleaseInfo(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        }
    }

    public func getAvailableManifests(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws -> [String: (toolsVersion: ToolsVersion, content: String?)] {
        guard let registryIdentity = package.registry else {
            throw RegistryError.invalidPackageIdentity(package)
        }

        guard let registry = self.configuration.registry(for: registryIdentity.scope) else {
            throw RegistryError.registryNotConfigured(scope: registryIdentity.scope)
        }

        if registry.supportsAvailability {
            try await self.checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }

        return try await self._getAvailableManifests(
            registry: registry,
            package: registryIdentity,
            version: version,
            timeout: timeout,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _getAvailableManifests(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) async throws -> [String: (toolsVersion: ToolsVersion, content: String?)] {
        // first get the release metadata to see if archive is signed (therefore manifest is also signed)
        let versionMetadata = try await self._getPackageVersionMetadata(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            fileSystem: localFileSystem,
            observabilityScope: observabilityScope
        )

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents(
            "\(package.scope)",
            "\(package.name)",
            "\(version)",
            Manifest.filename
        )

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .swift),
            ],
            options: self.defaultRequestOptions(timeout: timeout)
        )

        // signature validation helper
        let signatureValidation = SignatureValidation(
            skipSignatureValidation: self.skipSignatureValidation,
            signingEntityStorage: self.signingEntityStorage,
            signingEntityCheckingMode: self.signingEntityCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata },
            delegate: RegistryClientSignatureValidationDelegate(underlying: self.delegate)
        )

        // checksum TOFU validation helper
        let checksumTOFU = PackageVersionChecksumTOFU(
            fingerprintStorage: self.fingerprintStorage,
            fingerprintCheckingMode: self.fingerprintCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata }
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "retrieving available manifests for \(package) \(version) from \(request.url)")

        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)

            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                try response.validateAPIVersion()
                try response.validateContentType(.swift)

                guard let data = response.body else {
                    throw RegistryError.invalidResponse
                }
                guard let manifestContent = String(data: data, encoding: .utf8) else {
                    throw RegistryError.invalidResponse
                }

                _ = try await signatureValidation.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    toolsVersion: .none,
                    manifestContent: manifestContent,
                    configuration: self.configuration.signing(for: package, registry: registry),
                    timeout: timeout,
                    fileSystem: localFileSystem,
                    observabilityScope: observabilityScope
                )

                // TODO: expose Data based API on checksumAlgorithm
                let actualChecksum = self.checksumAlgorithm.hash(.init(data))
                    .hexadecimalRepresentation

                let checksumResult = try await checksumTOFU.validateManifest(
                    registry: registry,
                    package: package,
                    version: version,
                    toolsVersion: .none,
                    checksum: actualChecksum,
                    timeout: timeout,
                    observabilityScope: observabilityScope
                )
                var result = [String: (toolsVersion: ToolsVersion, content: String?)]()
                let toolsVersion = try ToolsVersionParser.parse(utf8String: manifestContent)
                result[Manifest.filename] = (
                    toolsVersion: toolsVersion,
                    content: manifestContent
                )

                // checksum TOFU validation helper
                let checksumTOFU = PackageVersionChecksumTOFU(
                    fingerprintStorage: self.fingerprintStorage,
                    fingerprintCheckingMode: self.fingerprintCheckingMode,
                    versionMetadataProvider: { _, _ in versionMetadata }
                )

                let start = DispatchTime.now()
                observabilityScope
                    .emit(info: "retrieving available manifests for \(package) \(version) from \(request.url)")
                self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
                    switch result {
                    case .success(let response):
                        do {
                            observabilityScope
                                .emit(
                                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                                )
                            switch response.statusCode {
                            case 200:
                                try response.validateAPIVersion()
                                try response.validateContentType(.swift)

                                guard let data = response.body else {
                                    throw RegistryError.invalidResponse
                                }
                                let manifestContent = String(decoding: data, as: UTF8.self)

                                signatureValidation.validate(
                                    registry: registry,
                                    package: package,
                                    version: version,
                                    toolsVersion: .none,
                                    manifestContent: manifestContent,
                                    configuration: self.configuration.signing(for: package, registry: registry),
                                    timeout: timeout,
                                    fileSystem: localFileSystem,
                                    observabilityScope: observabilityScope,
                                    callbackQueue: callbackQueue
                                ) { signatureResult in
                                    switch signatureResult {
                                    case .success:
                                        // TODO: expose Data based API on checksumAlgorithm
                                        let actualChecksum = self.checksumAlgorithm.hash(.init(data))
                                            .hexadecimalRepresentation

                                        checksumTOFU.validateManifest(
                                            registry: registry,
                                            package: package,
                                            version: version,
                                            toolsVersion: .none,
                                            checksum: actualChecksum,
                                            timeout: timeout,
                                            observabilityScope: observabilityScope,
                                            callbackQueue: callbackQueue
                                        ) { checksumResult in
                                            switch checksumResult {
                                            case .success:
                                                do {
                                                    var result =
                                                        [String: (toolsVersion: ToolsVersion, content: String?)]()
                                                    let toolsVersion = try ToolsVersionParser
                                                        .parse(utf8String: manifestContent)
                                                    result[Manifest.filename] = (
                                                        toolsVersion: toolsVersion,
                                                        content: manifestContent
                                                    )

                                                    let alternativeManifests = try response.headers.parseManifestLinks()
                                                    for alternativeManifest in alternativeManifests {
                                                        result[alternativeManifest.filename] = (
                                                            toolsVersion: alternativeManifest.toolsVersion,
                                                            content: .none
                                                        )
                                                    }
                                                    completion(.success(result))
                                                } catch {
                                                    completion(.failure(
                                                        RegistryError.failedRetrievingManifest(
                                                            registry: registry,
                                                            package: package.underlying,
                                                            version: version,
                                                            error: error
                                                        )
                                                    ))
                                                }
                                            case .failure(let error):
                                                completion(.failure(error))
                                            }
                                        }
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            case 404:
                                throw RegistryError.packageVersionNotFound
                            default:
                                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
                            }
                        } catch {
                            completion(.failure(
                                RegistryError.failedRetrievingManifest(
                                    registry: registry,
                                    package: package.underlying,
                                    version: version,
                                    error: error
                                )
                            ))
                        }
                    case .failure(let error):
                        completion(.failure(
                            RegistryError.failedRetrievingManifest(
                                registry: registry,
                                package: package.underlying,
                                version: version,
                                error: error
                            )
                        ))
                    }
                }
                return result

            case 404:
                throw RegistryError.packageVersionNotFound
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
            }
        } catch {
            throw RegistryError.failedRetrievingManifest(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        }
    }

    public func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws -> String {
        guard let registryIdentity = package.registry else {
            throw RegistryError.invalidPackageIdentity(package)
        }

        guard let registry = self.configuration.registry(for: registryIdentity.scope) else {
            throw RegistryError.registryNotConfigured(scope: registryIdentity.scope)
        }


        if registry.supportsAvailability {
            try await self.checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }
        return try await self._getManifestContent(
            registry: registry,
            package: registryIdentity,
            version: version,
            customToolsVersion: customToolsVersion,
            timeout: timeout,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _getManifestContent(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) async throws -> String {
        // first get the release metadata to see if archive is signed (therefore manifest is also signed)
        let versionMetadata = try await self._getPackageVersionMetadata(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            fileSystem: localFileSystem,
            observabilityScope: observabilityScope
        )

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents(
            "\(package.scope)",
            "\(package.name)",
            "\(version)",
            Manifest.filename
        )

        if let toolsVersion = customToolsVersion {
            components.queryItems = [
                URLQueryItem(name: "swift-version", value: toolsVersion.description),
            ]
        }

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .swift),
            ],
            options: self.defaultRequestOptions(timeout: timeout)
        )

        // signature validation helper
        let signatureValidation = SignatureValidation(
            skipSignatureValidation: self.skipSignatureValidation,
            signingEntityStorage: self.signingEntityStorage,
            signingEntityCheckingMode: self.signingEntityCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata },
            delegate: RegistryClientSignatureValidationDelegate(underlying: self.delegate)
        )

        // checksum TOFU validation helper
        let checksumTOFU = PackageVersionChecksumTOFU(
            fingerprintStorage: self.fingerprintStorage,
            fingerprintCheckingMode: self.fingerprintCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata }
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "retrieving \(package) \(version) manifest from \(request.url)")

        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope)

            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                try response.validateAPIVersion(isOptional: true)
                try response.validateContentType(.swift)

                guard let data = response.body else {
                    throw RegistryError.invalidResponse
                }
                guard let manifestContent = String(data: data, encoding: .utf8) else {
                    throw RegistryError.invalidResponse
                }

                _ = try await signatureValidation.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    toolsVersion: customToolsVersion,
                    manifestContent: manifestContent,
                    configuration: self.configuration.signing(for: package, registry: registry),
                    timeout: timeout,
                    fileSystem: localFileSystem,
                    observabilityScope: observabilityScope
                )

                // TODO: expose Data based API on checksumAlgorithm
                let actualChecksum = self.checksumAlgorithm.hash(.init(data))
                    .hexadecimalRepresentation

                try await checksumTOFU.validateManifest(
                    registry: registry,
                    package: package,
                    version: version,
                    toolsVersion: customToolsVersion,
                    checksum: actualChecksum,
                    timeout: timeout,
                    observabilityScope: observabilityScope
                )

                // checksum TOFU validation helper
                let checksumTOFU = PackageVersionChecksumTOFU(
                    fingerprintStorage: self.fingerprintStorage,
                    fingerprintCheckingMode: self.fingerprintCheckingMode,
                    versionMetadataProvider: { _, _ in versionMetadata }
                )

                let start = DispatchTime.now()
                observabilityScope.emit(info: "retrieving \(package) \(version) manifest from \(request.url)")
                self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
                    switch result {
                    case .success(let response):
                        do {
                            observabilityScope
                                .emit(
                                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                                )
                            switch response.statusCode {
                            case 200:
                                try response.validateAPIVersion(isOptional: true)
                                try response.validateContentType(.swift)

                                guard let data = response.body else {
                                    throw RegistryError.invalidResponse
                                }
                                let manifestContent = String(decoding: data, as: UTF8.self)

                                signatureValidation.validate(
                                    registry: registry,
                                    package: package,
                                    version: version,
                                    toolsVersion: customToolsVersion,
                                    manifestContent: manifestContent,
                                    configuration: self.configuration.signing(for: package, registry: registry),
                                    timeout: timeout,
                                    fileSystem: localFileSystem,
                                    observabilityScope: observabilityScope,
                                    callbackQueue: callbackQueue
                                ) { signatureResult in
                                    switch signatureResult {
                                    case .success:
                                        // TODO: expose Data based API on checksumAlgorithm
                                        let actualChecksum = self.checksumAlgorithm.hash(.init(data))
                                            .hexadecimalRepresentation

                                        checksumTOFU.validateManifest(
                                            registry: registry,
                                            package: package,
                                            version: version,
                                            toolsVersion: customToolsVersion,
                                            checksum: actualChecksum,
                                            timeout: timeout,
                                            observabilityScope: observabilityScope,
                                            callbackQueue: callbackQueue
                                        ) { checksumResult in
                                            switch checksumResult {
                                            case .success:
                                                completion(.success(manifestContent))
                                            case .failure(let error):
                                                completion(.failure(error))
                                            }
                                        }
                                    case .failure(let error):
                                        completion(.failure(error))
                                    }
                                }
                            case 404:
                                throw RegistryError.packageVersionNotFound
                            default:
                                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
                            }
                        } catch {
                            completion(.failure(
                                RegistryError.failedRetrievingManifest(
                                    registry: registry,
                                    package: package.underlying,
                                    version: version,
                                    error: error
                                )
                            ))
                        }
                    case .failure(let error):
                        completion(.failure(
                            RegistryError.failedRetrievingManifest(
                                registry: registry,
                                package: package.underlying,
                                version: version,
                                error: error
                            )
                        ))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        } catch {
            throw RegistryError.failedRetrievingManifest(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        }
    }

    public func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        destinationPath: AbsolutePath,
        progressHandler: HTTPClient.ProgressHandler?,
        timeout: DispatchTimeInterval? = .none,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws {guard let registryIdentity = package.registry else {
            throw RegistryError.invalidPackageIdentity(package)
        }

        guard let registry = self.configuration.registry(for: registryIdentity.scope) else {
            throw RegistryError.registryNotConfigured(scope: registryIdentity.scope)
        }


        if registry.supportsAvailability {
            try await self.checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }

        try await self._downloadSourceArchive(
            registry: registry,
            package: registryIdentity,
            version: version,
            destinationPath: destinationPath,
            progressHandler: progressHandler,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _downloadSourceArchive(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        destinationPath: AbsolutePath,
        progressHandler: HTTPClient.ProgressHandler?,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws {
        // first get the release metadata
        // TODO: this should be included in the archive to save the extra HTTP call
        let versionMetadata = try await self._getPackageVersionMetadata(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        // download archive
        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents("\(package.scope)", "\(package.name)", "\(version).zip")

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        // prepare target download locations
        let downloadPath = destinationPath.appending(extension: "zip")

        // prepare directories
        if !fileSystem.exists(downloadPath.parentDirectory) {
            try fileSystem.createDirectory(downloadPath.parentDirectory, recursive: true)
        }
        // clear out download path if exists
        try fileSystem.removeFileTree(downloadPath)
        // validate that the destination does not already exist
        guard !fileSystem.exists(destinationPath) else {
            throw RegistryError.pathAlreadyExists(destinationPath)
        }

        // signature validation helper
        let signatureValidation = SignatureValidation(
            skipSignatureValidation: self.skipSignatureValidation,
            signingEntityStorage: self.signingEntityStorage,
            signingEntityCheckingMode: self.signingEntityCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata },
            delegate: RegistryClientSignatureValidationDelegate(underlying: self.delegate)
        )

        // checksum TOFU validation helper
        let checksumTOFU = PackageVersionChecksumTOFU(
            fingerprintStorage: self.fingerprintStorage,
            fingerprintCheckingMode: self.fingerprintCheckingMode,
            versionMetadataProvider: { _, _ in versionMetadata }
        )

        let request = HTTPClient.Request.download(
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .zip),
            ],
            options: self.defaultRequestOptions(timeout: timeout),
            fileSystem: fileSystem,
            destination: downloadPath
        )

        let downloadStart = DispatchTime.now()
        observabilityScope.emit(info: "downloading \(package) \(version) source archive from \(request.url)")

        do {
            let response = try await self.httpClient.execute(
                request,
                observabilityScope: observabilityScope,
                progress: progressHandler
            )

            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(downloadStart.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                try response.validateAPIVersion(isOptional: true)
                try response.validateContentType(.zip)

                let archiveContent: Data

                do {
                    archiveContent = try fileSystem.readFileContents(downloadPath)
                } catch {
                    throw RegistryError.failedToComputeChecksum(error)
                }

                // TODO: expose Data based API on checksumAlgorithm
                let actualChecksum = self.checksumAlgorithm.hash(.init(archiveContent))
                    .hexadecimalRepresentation

                observabilityScope
                    .emit(
                        debug: "performing TOFU checks on \(package) \(version) source archive (checksum: '\(actualChecksum)'"
                    )
                let signingEntity = try await signatureValidation.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    content: archiveContent,
                    configuration: self.configuration.signing(for: package, registry: registry),
                    timeout: timeout,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )

                try await checksumTOFU.validateSourceArchive(
                    registry: registry,
                    package: package,
                    version: version,
                    checksum: actualChecksum,
                    timeout: timeout,
                    observabilityScope: observabilityScope
                )

                // validate that the destination does not already exist
                // (again, as this
                // is
                // async)
                guard !fileSystem.exists(destinationPath) else {
                    throw RegistryError.pathAlreadyExists(destinationPath)
                }
                try fileSystem.createDirectory(
                    destinationPath,
                    recursive: true
                )
                // extract the content
                let extractStart = DispatchTime.now()
                observabilityScope
                    .emit(
                        debug: "extracting \(package) \(version) source archive to '\(destinationPath)'"
                    )
                let archiver = self.archiverProvider(fileSystem)

                // TODO: Bail if archive contains relative paths or overlapping files

                defer {
                    try? fileSystem.removeFileTree(downloadPath)
                }

                do {
                    try await archiver.extract(
                        from: downloadPath,
                        to: destinationPath
                    )

                    observabilityScope
                        .emit(
                            debug: "extracted \(package) \(version) source archive to '\(destinationPath)' in \(extractStart.distance(to: .now()).descriptionInSeconds)"
                        )

                    // strip first level component
                    try fileSystem
                        .stripFirstLevel(of: destinationPath)
                    // write down copy of version metadata
                    let registryMetadataPath = destinationPath
                        .appending(
                            component: RegistryReleaseMetadataStorage
                                .fileName
                        )
                    observabilityScope
                        .emit(
                            debug: "saving \(package) \(version) metadata to '\(registryMetadataPath)'"
                        )
                    try RegistryReleaseMetadataStorage.save(
                        metadata: versionMetadata,
                        signingEntity: signingEntity,
                        to: registryMetadataPath,
                        fileSystem: fileSystem
                    )
                } catch {
                    throw StringError(
                        "failed extracting '\(downloadPath)' to '\(destinationPath)': \(error.interpolationDescription)"
                    )
                }
            case 404:
                throw RegistryError.packageVersionNotFound
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
            }
        } catch {
          throw RegistryError.failedDownloadingSourceArchive(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        }
    }

    public func lookupIdentities(
        scmURL: SourceControlURL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws -> Set<PackageIdentity> {
        guard let registry = self.configuration.defaultRegistry else {
            throw RegistryError.registryNotConfigured(scope: nil)
        }

        if registry.supportsAvailability {
            try await self.checkAvailabilityCache(
                registry: registry,
                observabilityScope: observabilityScope
            )
        }

        return try await self._lookupIdentities(
            registry: registry,
            scmURL: scmURL,
            timeout: timeout,
            observabilityScope: observabilityScope
        )
    }

    // marked internal for testing
    func _lookupIdentities(
        registry: Registry,
        scmURL: SourceControlURL,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope
    ) async throws -> Set<PackageIdentity> {
        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents("identifiers")

        components.queryItems = [
            URLQueryItem(name: "url", value: scmURL.absoluteString),
        ]

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout)
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "looking up identity for \(scmURL) from \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)
            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                let packageIdentities = try response.parseJSON(
                    Serialization.PackageIdentifiers.self,
                    decoder: self.jsonDecoder
                )
                observabilityScope.emit(debug: "matched identities for \(scmURL): \(packageIdentities)")
                return Set(packageIdentities.identifiers.map {
                    PackageIdentity.plain($0)
                })
            case 404:
                // 404 is valid, no identities mapped
                return []
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
            }
        } catch {
            throw RegistryError.failedIdentityLookup(registry: registry, scmURL: scmURL, error: error)
        }
    }

    public func login(
        loginURL: URL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws {
        let request = HTTPClient.Request(
            method: .post,
            url: loginURL,
            options: self.defaultRequestOptions(timeout: timeout)
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "logging-in into \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)
            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                return
            default:
                let error = self.unexpectedStatusError(response, expectedStatus: [200])
                throw RegistryError.loginFailed(url: loginURL, error: error)
            }
        } catch {
            throw RegistryError.loginFailed(url: loginURL, error: error)
        }
    }

    public func publish(
        registryURL: URL,
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageArchive: AbsolutePath,
        packageMetadata: AbsolutePath?,
        signature: [UInt8]?,
        metadataSignature: [UInt8]?,
        signatureFormat: SignatureFormat?,
        timeout: DispatchTimeInterval? = .none,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> PublishResult {
        guard let registryIdentity = packageIdentity.registry else {
            throw RegistryError.invalidPackageIdentity(packageIdentity)
        }
        guard var components = URLComponents(url: registryURL, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registryURL)
        }
        components.appendPathComponents(registryIdentity.scope.description)
        components.appendPathComponents(registryIdentity.name.description)
        components.appendPathComponents(packageVersion.description)

        guard let url = components.url else {
            throw RegistryError.invalidURL(registryURL)
        }

        // TODO: don't load the entire file in memory
        guard let packageArchiveContent: Data = try? fileSystem.readFileContents(packageArchive) else {
            throw RegistryError.failedLoadingPackageArchive(packageArchive)
        }
        var metadataContent: String? = .none
        if let packageMetadata {
            do {
                metadataContent = try fileSystem.readFileContents(packageMetadata)
            } catch {
                throw RegistryError.failedLoadingPackageMetadata(packageMetadata)
            }
        }

        // TODO: add generic support for upload requests in Basics
        let boundary = UUID().uuidString
        var body = Data()

        // archive field
        body.append(contentsOf: """
        --\(boundary)\r
        Content-Disposition: form-data; name=\"source-archive\"\r
        Content-Type: application/zip\r
        Content-Transfer-Encoding: binary\r
        \r\n
        """.utf8)
        body.append(packageArchiveContent)

        if let signature {
            guard signatureFormat != nil else {
                throw RegistryError.missingSignatureFormat
            }

            body.append(contentsOf: """
            \r
            --\(boundary)\r
            Content-Disposition: form-data; name=\"source-archive-signature\"\r
            Content-Type: application/octet-stream\r
            Content-Transfer-Encoding: binary\r
            \r\n
            """.utf8)
            body.append(contentsOf: signature)
        }

        // metadata field
        if let metadataContent {
            body.append(contentsOf: """
            \r
            --\(boundary)\r
            Content-Disposition: form-data; name=\"metadata\"\r
            Content-Type: application/json\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            \(metadataContent)
            """.utf8)

            if signature != nil {
                guard metadataSignature != nil else {
                    throw RegistryError.invalidSignature(reason: "both archive and metadata must be signed")
                }
            }

            if let metadataSignature {
                guard signature != nil else {
                    throw RegistryError.invalidSignature(reason: "both archive and metadata must be signed")
                }
                guard signatureFormat != nil else {
                    throw RegistryError.missingSignatureFormat
                }

                body.append(contentsOf: """
                \r
                --\(boundary)\r
                Content-Disposition: form-data; name=\"metadata-signature\"\r
                Content-Type: application/octet-stream\r
                Content-Transfer-Encoding: binary\r
                \r\n
                """.utf8)
                body.append(contentsOf: metadataSignature)
            }
        }

        // footer
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        var request = HTTPClient.Request(
            method: .put,
            url: url,
            headers: [
                "Content-Type": "multipart/form-data;boundary=\"\(boundary)\"",
                "Accept": self.acceptHeader(mediaType: .json),
                "Expect": "100-continue",
                "Prefer": "respond-async",
            ],
            body: body,
            options: self.defaultRequestOptions(timeout: timeout)
        )

        if signature != nil, let signatureFormat {
            request.headers.add(name: "X-Swift-Package-Signature-Format", value: signatureFormat.rawValue)
        }

        let start = DispatchTime.now()
        observabilityScope.emit(info: "publishing \(packageIdentity) \(packageVersion) to \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)

            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 201:
                try response.validateAPIVersion()
                let location = response.headers.get("Location").first.flatMap { URL(string: $0) }
                return PublishResult.published(location)
            case 202:
                try response.validateAPIVersion()

                guard let location = (response.headers.get("Location").first.flatMap { URL(string: $0) }) else {
                    throw RegistryError.missingPublishingLocation
                }
                let retryAfter = response.headers.get("Retry-After").first.flatMap { Int($0) }
                return PublishResult.processing(statusURL: location, retryAfter: retryAfter)
            default:
                throw self.unexpectedStatusError(response, expectedStatus: [201, 202])
            }
        } catch {
            throw RegistryError.failedPublishing(error)
        }
    }

    // marked internal for testing
    func checkAvailability(
        registry: Registry,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope
    ) async throws -> AvailabilityStatus {
        guard registry.supportsAvailability else {
            throw StringError("registry \(registry.url) does not support availability checks.")
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            throw RegistryError.invalidURL(registry.url)
        }
        components.appendPathComponents("availability")

        guard let url = components.url else {
            throw RegistryError.invalidURL(registry.url)
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            options: self.defaultRequestOptions(timeout: timeout)
        )

        let start = DispatchTime.now()
        observabilityScope.emit(info: "checking availability of \(registry.url) using \(request.url)")
        do {
            let response = try await self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil)
            observabilityScope
                .emit(
                    debug: "server response for \(request.url): \(response.statusCode) in \(start.distance(to: .now()).descriptionInSeconds)"
                )
            switch response.statusCode {
            case 200:
                return .available
            case let value where AvailabilityStatus.unavailableStatusCodes.contains(value):
                return .unavailable
            default:
                if let error = try? response.parseError(decoder: self.jsonDecoder) {
                    return .error(error.detail)
                }
                return .error("unknown server error (\(response.statusCode))")
            }
        } catch {
            throw RegistryError.availabilityCheckFailed(registry: registry, error: error)
        }
    }

    private func checkAvailabilityCache(
        registry: Registry,
        observabilityScope: ObservabilityScope
    ) async throws {
        let availabilityHandler: (Result<AvailabilityStatus, Error>) throws -> Void = { result in
            switch result {
            case .success(let status):
                switch status {
                case .available:
                    return
                case .unavailable:
                    throw RegistryError.registryNotAvailable(registry)
                case .error(let description):
                    throw StringError(description)
                }
            case .failure(let error):
                throw error
            }
        }

        if let cached = self.availabilityCache[registry.url], cached.expires < .now() {
            return try availabilityHandler(cached.status)
        }

        let result: Result<AvailabilityStatus, Error>
        do {
            result = try await .success(self.checkAvailability(
                registry: registry,
                observabilityScope: observabilityScope
            ))
        } catch {
            result = .failure(error)
        }

        self.availabilityCache[registry.url] = (status: result, expires: .now() + Self.availabilityCacheTTL)
        try availabilityHandler(result)
    }

    private func unexpectedStatusError(
        _ response: HTTPClientResponse,
        expectedStatus: [Int]
    ) -> Error {
        if let error = try? response.parseError(decoder: self.jsonDecoder) {
            return RegistryError.serverError(code: response.statusCode, details: error.detail)
        }

        switch response.statusCode {
        case 401:
            return RegistryError.unauthorized
        case 403:
            return RegistryError.forbidden
        case 400...499:
            return RegistryError.clientError(
                code: response.statusCode,
                details: response.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
            )
        case 501:
            return RegistryError.authenticationMethodNotSupported
        case 500...599:
            return RegistryError.serverError(
                code: response.statusCode,
                details: response.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
            )
        default:
            return RegistryError.invalidResponseStatus(expected: expectedStatus, actual: response.statusCode)
        }
    }

    private func defaultRequestOptions(
        timeout: DispatchTimeInterval? = .none
    ) -> HTTPClient.Request.Options {
        var options = HTTPClient.Request.Options()
        options.timeout = timeout
        options.authorizationProvider = self.authorizationProvider
        return options
    }

    private struct MetadataCacheKey: Hashable {
        let registry: Registry
        let package: PackageIdentity.RegistryIdentity
    }
}

public enum RegistryError: Error, CustomStringConvertible {
    case registryNotConfigured(scope: PackageIdentity.Scope?)
    case invalidPackageIdentity(PackageIdentity)
    case invalidURL(URL)
    case invalidResponseStatus(expected: [Int], actual: Int)
    case invalidContentVersion(expected: String, actual: String?)
    case invalidContentType(expected: String, actual: String?)
    case invalidResponse
    case missingSourceArchive
    case invalidSourceArchive
    case unsupportedHashAlgorithm(String)
    case failedToComputeChecksum(Error)
    case checksumChanged(latest: String, previous: String)
    case invalidChecksum(expected: String, actual: String)
    case pathAlreadyExists(AbsolutePath)
    case failedRetrievingReleases(registry: Registry, package: PackageIdentity, error: Error)
    case failedRetrievingReleaseInfo(registry: Registry, package: PackageIdentity, version: Version, error: Error)
    case failedRetrievingReleaseChecksum(registry: Registry, package: PackageIdentity, version: Version, error: Error)
    case failedRetrievingManifest(registry: Registry, package: PackageIdentity, version: Version, error: Error)
    case failedDownloadingSourceArchive(registry: Registry, package: PackageIdentity, version: Version, error: Error)
    case failedIdentityLookup(registry: Registry, scmURL: SourceControlURL, error: Error)
    case failedLoadingPackageArchive(AbsolutePath)
    case failedLoadingPackageMetadata(AbsolutePath)
    case failedPublishing(Error)
    case missingPublishingLocation
    case serverError(code: Int, details: String)
    case clientError(code: Int, details: String)
    case unauthorized
    case authenticationMethodNotSupported
    case forbidden
    case loginFailed(url: URL, error: Error)
    case availabilityCheckFailed(registry: Registry, error: Error)
    case registryNotAvailable(Registry)
    case packageNotFound
    case packageVersionNotFound
    case sourceArchiveMissingChecksum(registry: Registry, package: PackageIdentity, version: Version)
    case sourceArchiveNotSigned(registry: Registry, package: PackageIdentity, version: Version)
    case failedLoadingSignature
    case failedRetrievingSourceArchiveSignature(
        registry: Registry,
        package: PackageIdentity,
        version: Version,
        error: Error
    )
    case manifestNotSigned(registry: Registry, package: PackageIdentity, version: Version, toolsVersion: ToolsVersion?)
    case missingConfiguration(details: String)
    case badConfiguration(details: String)
    case missingSignatureFormat
    case unknownSignatureFormat(String)
    case invalidSignature(reason: String)
    case invalidSigningCertificate(reason: String)
    case signerNotTrusted(PackageIdentity, SigningEntity)
    case failedToValidateSignature(Error)
    case signingEntityForReleaseChanged(
        registry: Registry,
        package: PackageIdentity,
        version: Version,
        latest: SigningEntity?,
        previous: SigningEntity
    )
    case signingEntityForPackageChanged(
        registry: Registry,
        package: PackageIdentity,
        version: Version,
        latest: SigningEntity?,
        previous: SigningEntity,
        previousVersion: Version
    )

    public var description: String {
        switch self {
        case .registryNotConfigured(let scope):
            if let scope {
                return "no registry configured for '\(scope)' scope"
            } else {
                return "no registry configured'"
            }
        case .invalidPackageIdentity(let packageIdentity):
            return "invalid package identifier '\(packageIdentity)'"
        case .invalidURL(let url):
            return "invalid URL '\(url)'"
        case .invalidResponseStatus(let expected, let actual):
            return "invalid registry response status '\(actual)', expected '\(expected)'"
        case .invalidContentVersion(let expected, let actual):
            return "invalid registry response content version '\(actual ?? "")', expected '\(expected)'"
        case .invalidContentType(let expected, let actual):
            return "invalid registry response content type '\(actual ?? "")', expected '\(expected)'"
        case .invalidResponse:
            return "invalid registry response"
        case .missingSourceArchive:
            return "missing registry source archive"
        case .invalidSourceArchive:
            return "invalid registry source archive"
        case .unsupportedHashAlgorithm(let algorithm):
            return "unsupported hash algorithm '\(algorithm)'"
        case .failedToComputeChecksum(let error):
            return "failed computing registry source archive checksum: \(error.interpolationDescription)"
        case .checksumChanged(let latest, let previous):
            return "the latest checksum '\(latest)' is different from the previously recorded value '\(previous)'"
        case .invalidChecksum(let expected, let actual):
            return "invalid registry source archive checksum '\(actual)', expected '\(expected)'"
        case .pathAlreadyExists(let path):
            return "path already exists '\(path)'"
        case .failedRetrievingReleases(let registry, let packageIdentity, let error):
            return "failed fetching \(packageIdentity) releases list from \(registry): \(error.interpolationDescription)"
        case .failedRetrievingReleaseInfo(let registry, let packageIdentity, let version, let error):
            return "failed fetching \(packageIdentity) version \(version) release information from \(registry): \(error.interpolationDescription)"
        case .failedRetrievingReleaseChecksum(let registry, let packageIdentity, let version, let error):
            return "failed fetching \(packageIdentity) version \(version) release checksum from \(registry): \(error.interpolationDescription)"
        case .failedRetrievingManifest(let registry, let packageIdentity, let version, let error):
            return "failed retrieving \(packageIdentity) version \(version) manifest from \(registry): \(error.interpolationDescription)"
        case .failedDownloadingSourceArchive(let registry, let packageIdentity, let version, let error):
            return "failed downloading \(packageIdentity) version \(version) source archive from \(registry): \(error.interpolationDescription)"
        case .failedIdentityLookup(let registry, let scmURL, let error):
            return "failed looking up identity for \(scmURL) on \(registry): \(error.interpolationDescription)"
        case .failedLoadingPackageArchive(let path):
            return "failed loading package archive at '\(path)' for publishing"
        case .failedLoadingPackageMetadata(let path):
            return "failed loading package metadata at '\(path)' for publishing"
        case .failedPublishing(let error):
            return "failed publishing: \(error.interpolationDescription)"
        case .missingPublishingLocation:
            return "response missing registry source archive"
        case .serverError(let code, let details):
            return "server error \(code): \(details)"
        case .clientError(let code, let details):
            return "client error \(code): \(details)"
        case .unauthorized:
            return "missing or invalid authentication credentials"
        case .authenticationMethodNotSupported:
            return "authentication method not supported"
        case .forbidden:
            return "forbidden"
        case .availabilityCheckFailed(let registry, let error):
            return "failed checking availability of registry at '\(registry.url)': \(error.interpolationDescription)"
        case .registryNotAvailable(let registry):
            return "registry at '\(registry.url)' is not available at this time, please try again later"
        case .packageNotFound:
            return "package not found on registry"
        case .packageVersionNotFound:
            return "package version not found on registry"
        case .sourceArchiveMissingChecksum(let registry, let packageIdentity, let version):
            return "\(packageIdentity) version \(version) source archive from \(registry) has no checksum"
        case .sourceArchiveNotSigned(let registry, let packageIdentity, let version):
            return "\(packageIdentity) version \(version) source archive from \(registry) is not signed"
        case .failedLoadingSignature:
            return "failed loading signature for validation"
        case .failedRetrievingSourceArchiveSignature(let registry, let packageIdentity, let version, let error):
            return "failed retrieving '\(packageIdentity)' version \(version) source archive signature from '\(registry)': \(error.interpolationDescription)"
        case .manifestNotSigned(let registry, let packageIdentity, let version, let toolsVersion):
            return "manifest for \(packageIdentity) version \(version) tools version \(toolsVersion.map { "\($0)" } ?? "unspecified") from \(registry) is not signed"
        case .missingConfiguration(let details):
            return "unable to proceed because of missing configuration: \(details)"
        case .badConfiguration(let details):
            return "unable to proceed because of bad configuration: \(details)"
        case .missingSignatureFormat:
            return "missing signature format"
        case .unknownSignatureFormat(let format):
            return "unknown signature format: \(format)"
        case .invalidSignature(let reason):
            return "signature is invalid: \(reason)"
        case .invalidSigningCertificate(let reason):
            return "the signing certificate is invalid: \(reason)"
        case .signerNotTrusted(_, let signingEntity):
            return "the signer \(signingEntity) is not trusted"
        case .failedToValidateSignature(let error):
            return "failed to validate signature: \(error.interpolationDescription)"
        case .signingEntityForReleaseChanged(let registry, let package, let version, let latest, let previous):
            return "the signing entity '\(String(describing: latest))' from \(registry) for \(package) version \(version) is different from the previously recorded value '\(previous)'"
        case .signingEntityForPackageChanged(
            let registry,
            let package,
            let version,
            let latest,
            let previous,
            let previousVersion
        ):
            return "the signing entity '\(String(describing: latest))' from \(registry) for \(package) version \(version) is different from the previously recorded value '\(previous)' for version \(previousVersion)"
        case .loginFailed(let url, let error):
            return "registry login using \(url) failed: \(error.interpolationDescription)"
        }
    }
}

extension RegistryClient {
    fileprivate enum APIVersion: String {
        case v1 = "1"
    }
}

extension RegistryClient {
    fileprivate enum MediaType: String {
        case json
        case swift
        case zip
    }

    fileprivate enum ContentType: String, CaseIterable {
        case json = "application/json"
        case swift = "text/x-swift"
        case zip = "application/zip"
        case error = "application/problem+json"
    }

    private func acceptHeader(mediaType: MediaType) -> String {
        "application/vnd.swift.registry.v\(Self.apiVersion.rawValue)+\(mediaType)"
    }
}

extension RegistryClient {
    public struct PackageMetadata {
        public let registry: Registry
        public let versions: [Version]
        public let alternateLocations: [SourceControlURL]?
    }

    public struct PackageVersionMetadata: Sendable {
        public let registry: Registry
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let repositoryURLs: [SourceControlURL]?
        public let resources: [Resource]
        public let author: Author?
        public let description: String?
        public let publishedAt: Date?

        public var sourceArchive: Resource? {
            self.resources.first(where: { $0.name == "source-archive" })
        }

        public struct Resource: Sendable {
            public let name: String
            public let type: String
            public let checksum: String?
            public let signing: Signing?
            public let signingEntity: SigningEntity?

            public init(
                name: String,
                type: String,
                checksum: String?,
                signing: Signing?,
                signingEntity: SigningEntity?
            ) {
                self.name = name
                self.type = type
                self.checksum = checksum
                self.signing = signing
                self.signingEntity = signingEntity
            }
        }

        public struct Signing: Sendable {
            public let signatureBase64Encoded: String
            public let signatureFormat: String
        }

        public struct Author: Sendable {
            public let name: String
            public let email: String?
            public let description: String?
            public let organization: Organization?
            public let url: URL?
        }

        public struct Organization: Sendable {
            public let name: String
            public let email: String?
            public let description: String?
            public let url: URL?
        }
    }
}

extension RegistryClient {
    fileprivate struct AlternativeLocationLink {
        let url: SourceControlURL
        let kind: Kind

        enum Kind: String {
            case canonical
            case alternate
        }
    }
}

extension RegistryClient {
    fileprivate struct ManifestLink {
        let url: URL
        let filename: String
        let toolsVersion: ToolsVersion
    }
}

extension RegistryClient {
    public enum PublishResult: Equatable {
        case published(URL?)
        case processing(statusURL: URL, retryAfter: Int?)
    }
}

extension RegistryClient {
    public enum AvailabilityStatus: Equatable {
        case available
        case unavailable
        case error(String)

        // marked internal for testing
        static var unavailableStatusCodes = [404, 501]
    }
}

extension RegistryClient {
    struct ServerError: Decodable {
        let detail: String
    }

    struct RatelimitError {
        let retryAfter: Int
    }
}

extension HTTPClientResponse {
    fileprivate func parseJSON<T>(_ type: T.Type, decoder: JSONDecoder) throws -> T where T: Decodable {
        try self.validateAPIVersion()
        try self.validateContentType(.json)

        guard let data = self.body else {
            throw RegistryError.invalidResponse
        }

        return try decoder.decode(type, from: data)
    }

    fileprivate func parseError(
        decoder: JSONDecoder
    ) throws -> RegistryClient.ServerError {
        try self.validateAPIVersion()
        try self.validateContentType(.error)

        guard let data = self.body else {
            throw RegistryError.invalidResponse
        }

        return try decoder.decode(RegistryClient.ServerError.self, from: data)
    }
}

extension HTTPClientResponse {
    private func validateStatusCode(_ expectedStatusCodes: [Int]) throws {
        guard expectedStatusCodes.contains(self.statusCode) else {
            throw RegistryError.invalidResponseStatus(expected: expectedStatusCodes, actual: self.statusCode)
        }
    }

    fileprivate func validateAPIVersion(
        _ expectedVersion: RegistryClient.APIVersion = .v1,
        isOptional: Bool = false
    ) throws {
        let apiVersion = self.apiVersion

        if isOptional, apiVersion == nil {
            return
        }

        // Check API version as long as `Content-Version` is set
        guard apiVersion == expectedVersion else {
            throw RegistryError.invalidContentVersion(
                expected: expectedVersion.rawValue,
                actual: self.apiVersion?.rawValue
            )
        }
    }

    fileprivate func validateContentType(_ expectedContentType: RegistryClient.ContentType) throws {
        guard self.contentType == expectedContentType else {
            throw RegistryError.invalidContentType(
                expected: expectedContentType.rawValue,
                actual: self.contentType?.rawValue
            )
        }
    }

    fileprivate var apiVersion: RegistryClient.APIVersion? {
        self.headers.get("Content-Version").first.flatMap { headerValue in
            RegistryClient.APIVersion(rawValue: headerValue)
        }
    }

    private var contentType: RegistryClient.ContentType? {
        self.headers.get("Content-Type").first.flatMap { headerValue in
            if let contentType = RegistryClient.ContentType(rawValue: headerValue) {
                return contentType
            }
            if let contentType = RegistryClient.ContentType.allCases.first(where: {
                headerValue.hasPrefix($0.rawValue + ";")
            }) {
                return contentType
            }
            return nil
        }
    }
}

extension HTTPClientHeaders {
    /*
     <https://github.com/mona/LinkedList>; rel="canonical",
     <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
      */
    fileprivate func parseAlternativeLocationLinks() throws -> [RegistryClient.AlternativeLocationLink]? {
        try self.get("Link").map { header -> [RegistryClient.AlternativeLocationLink] in
            let linkLines = header.split(separator: ",").map(String.init).map { $0.spm_chuzzle() ?? $0 }
            return try linkLines.compactMap { linkLine in
                try parseAlternativeLocationLine(linkLine)
            }
        }.flatMap { $0 }
    }

    private func parseAlternativeLocationLine(_ value: String) throws -> RegistryClient.AlternativeLocationLink? {
        let fields = value.split(separator: ";")
            .map(String.init)
            .map { $0.spm_chuzzle() ?? $0 }

        guard fields.count == 2 else {
            return nil
        }

        guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) })
        else {
            return nil
        }

        guard let rel = fields.first(where: { $0.hasPrefix("rel=") }).flatMap({ parseLinkFieldValue($0) }),
              let kind = RegistryClient.AlternativeLocationLink.Kind(rawValue: rel)
        else {
            return nil
        }

        return RegistryClient.AlternativeLocationLink(
            url: SourceControlURL(link),
            kind: kind
        )
    }
}

extension HTTPClientHeaders {
    /*
     <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0"
     */
    fileprivate func parseManifestLinks() throws -> [RegistryClient.ManifestLink] {
        try self.get("Link").map { header -> [RegistryClient.ManifestLink] in
            let linkLines = header.split(separator: ",").map(String.init).map { $0.spm_chuzzle() ?? $0 }
            return try linkLines.compactMap { linkLine in
                try parseManifestLinkLine(linkLine)
            }
        }.flatMap { $0 }
    }

    private func parseManifestLinkLine(_ value: String) throws -> RegistryClient.ManifestLink? {
        let fields = value.split(separator: ";")
            .map(String.init)
            .map { $0.spm_chuzzle() ?? $0 }

        guard fields.count == 4 else {
            return nil
        }

        guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) }),
              let url = URL(string: link)
        else {
            return nil
        }

        guard let rel = fields.first(where: { $0.hasPrefix("rel=") }).flatMap({ parseLinkFieldValue($0) }),
              rel == "alternate"
        else {
            return nil
        }

        guard let filename = fields.first(where: { $0.hasPrefix("filename=") }).flatMap({ parseLinkFieldValue($0) })
        else {
            return nil
        }

        guard let toolsVersion = fields.first(where: { $0.hasPrefix("swift-tools-version=") })
            .flatMap({ parseLinkFieldValue($0) })
        else {
            return nil
        }

        guard let toolsVersion = ToolsVersion(string: toolsVersion) else {
            throw StringError("Invalid tools version in alternate manifest link '\(value)'")
        }

        return RegistryClient.ManifestLink(
            url: url,
            filename: filename,
            toolsVersion: toolsVersion
        )
    }
}

extension HTTPClientHeaders {
    private func parseLinkFieldValue(_ field: String) -> String? {
        let parts = field.split(separator: "=")
            .map(String.init)
            .map { $0.spm_chuzzle() ?? $0 }

        guard parts.count == 2 else {
            return nil
        }

        return parts[1].replacingOccurrences(of: "\"", with: "")
    }
}

// MARK: - Serialization

extension RegistryClient {
    // marked public for testing (cross module visibility)
    public enum Serialization {
        // marked public for testing (cross module visibility)
        public struct PackageMetadata: Codable {
            public let releases: [String: Release]

            public init(releases: [String: Release]) {
                self.releases = releases
            }

            public struct Release: Codable {
                public var url: String?
                public var problem: Problem?

                public init(url: String?, problem: Problem? = .none) {
                    self.url = url
                    self.problem = problem
                }
            }

            public struct Problem: Codable {
                public var status: Int?
                public var title: String?
                public var detail: String

                public init(status: Int, title: String, detail: String) {
                    self.status = status
                    self.title = title
                    self.detail = detail
                }
            }
        }

        // marked public for testing (cross module visibility)
        public struct VersionMetadata: Codable {
            public let id: String
            public let version: String
            public let resources: [Resource]
            public let metadata: AdditionalMetadata?
            public let publishedAt: Date?

            var sourceArchive: Resource? {
                self.resources.first(where: { $0.name == "source-archive" })
            }

            public init(
                id: String,
                version: String,
                resources: [Resource],
                metadata: AdditionalMetadata?,
                publishedAt: Date?
            ) {
                self.id = id
                self.version = version
                self.resources = resources
                self.metadata = metadata
                self.publishedAt = publishedAt
            }

            public struct Resource: Codable {
                public let name: String
                public let type: String
                public let checksum: String?
                public let signing: Signing?

                public init(name: String, type: String, checksum: String, signing: Signing?) {
                    self.name = name
                    self.type = type
                    self.checksum = checksum
                    self.signing = signing
                }
            }

            public struct Signing: Codable {
                public let signatureBase64Encoded: String
                public let signatureFormat: String
            }

            public struct AdditionalMetadata: Codable {
                public let author: Author?
                public let description: String?
                public let licenseURL: String?
                public let readmeURL: String?
                public let repositoryURLs: [String]?
                public let originalPublicationTime: Date?

                public init(
                    author: Author? = nil,
                    description: String,
                    licenseURL: String? = nil,
                    readmeURL: String? = nil,
                    repositoryURLs: [String]? = nil,
                    originalPublicationTime: Date? = nil
                ) {
                    self.author = author
                    self.description = description
                    self.licenseURL = licenseURL
                    self.readmeURL = readmeURL
                    self.repositoryURLs = repositoryURLs
                    self.originalPublicationTime = originalPublicationTime
                }
            }

            public struct Author: Codable {
                public let name: String
                public let email: String?
                public let description: String?
                public let organization: Organization?
                public let url: String?
            }

            public struct Organization: Codable {
                public let name: String
                public let email: String?
                public let description: String?
                public let url: String?
            }
        }

        // marked public for testing (cross module visibility)
        public struct PackageIdentifiers: Codable {
            public let identifiers: [String]

            public init(identifiers: [String]) {
                self.identifiers = identifiers
            }
        }
    }
}

// MARK: - RegistryReleaseMetadata serialization helpers

extension RegistryReleaseMetadataStorage {
    fileprivate static func save(
        metadata: RegistryClient.PackageVersionMetadata,
        signingEntity: SigningEntity?,
        to path: AbsolutePath,
        fileSystem: FileSystem
    ) throws {
        let registryMetadata = try RegistryReleaseMetadata(
            metadata: metadata,
            signingEntity: signingEntity
        )
        try self.save(registryMetadata, to: path, fileSystem: fileSystem)
    }
}

extension RegistryReleaseMetadata {
    fileprivate init(
        metadata: RegistryClient.PackageVersionMetadata,
        signingEntity: PackageSigning.SigningEntity?
    ) throws {
        self.init(
            source: .registry(metadata.registry.url),
            metadata: .init(
                author: metadata.author.flatMap {
                    .init(
                        name: $0.name,
                        emailAddress: $0.email,
                        description: $0.description,
                        url: $0.url,
                        organization: $0.organization.flatMap {
                            .init(
                                name: $0.name,
                                emailAddress: $0.email,
                                description: $0.description,
                                url: $0.url
                            )
                        }
                    )
                },
                description: metadata.description,
                licenseURL: metadata.licenseURL,
                readmeURL: metadata.readmeURL,
                scmRepositoryURLs: metadata.repositoryURLs
            ),
            signature: try metadata.sourceArchive?.signing.flatMap {
                guard let signatureData = Data(base64Encoded: $0.signatureBase64Encoded) else {
                    throw StringError("invalid based64 encoded signature")
                }
                return RegistrySignature(
                    signedBy: signingEntity.flatMap {
                        switch $0 {
                        case .recognized(let type, let name, let organizationalUnit, let organization):
                            return .recognized(
                                type: type.rawValue,
                                commonName: name,
                                organization: organization,
                                identity: organizationalUnit
                            )
                        case .unrecognized(let name, _, let organization):
                            return .unrecognized(commonName: name, organization: organization)
                        }
                    },
                    format: $0.signatureFormat,
                    value: Array(signatureData)
                )
            }
        )
    }
}

private struct RegistryClientSignatureValidationDelegate: SignatureValidation.Delegate {
    let underlying: RegistryClient.Delegate?

    private let onUnsignedResponseCache = ThreadSafeKeyValueStore<ResponseCacheKey, Bool>()
    private let onUntrustedResponseCache = ThreadSafeKeyValueStore<ResponseCacheKey, Bool>()

    func onUnsigned(
        registry: Registry,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version
    ) async -> Bool {
        let responseCacheKey = ResponseCacheKey(registry: registry, package: package, version: version)
        if let cachedResponse = self.onUnsignedResponseCache[responseCacheKey] {
            return cachedResponse
        }

        if let underlying {
            let response = await underlying.onUnsigned(
                registry: registry,
                package: package,
                version: version
            )

            self.onUnsignedResponseCache[responseCacheKey] = response
            return response
        } else {
            // true == continue resolution
            // false == stop dependency resolution
            return false
        }
    }

    func onUntrusted(
        registry: Registry,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version
    ) async -> Bool {
        let responseCacheKey = ResponseCacheKey(registry: registry, package: package, version: version)
        if let cachedResponse = self.onUntrustedResponseCache[responseCacheKey] {
            return cachedResponse
        }

        if let underlying {
            let response = await underlying.onUntrusted(
                registry: registry,
                package: package,
                version: version
            )
            self.onUntrustedResponseCache[responseCacheKey] = response
            return response
        } else {
            // true == continue resolution
            // false == stop dependency resolution
            return false
        }
    }

    private struct ResponseCacheKey: Hashable {
        let registry: Registry
        let package: PackageModel.PackageIdentity
        let version: TSCUtility.Version
    }
}

// MARK: - Utilities

extension URLComponents {
    fileprivate mutating func appendPathComponents(_ components: String...) {
        path += (path.last == "/" ? "" : "/") + components.joined(separator: "/")
    }
}
