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
import TSCBasic

import struct TSCUtility.Version

/// Package registry client.
/// API specification: https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md
public final class RegistryClient: Cancellable {
    private let apiVersion: APIVersion = .v1

    private let configuration: RegistryConfiguration
    private let archiverProvider: (FileSystem) -> Archiver
    private let httpClient: LegacyHTTPClient
    private let authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?
    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode
    private let jsonDecoder: JSONDecoder

    public init(
        configuration: RegistryConfiguration,
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        authorizationProvider: AuthorizationProvider? = .none,
        customHTTPClient: LegacyHTTPClient? = .none,
        customArchiverProvider: ((FileSystem) -> Archiver)? = .none
    ) {
        self.configuration = configuration

        if let authorizationProvider = authorizationProvider {
            self.authorizationProvider = { url in
                guard let registryAuthentication = configuration.authentication(for: url) else {
                    return .none
                }
                guard let (user, password) = authorizationProvider.authentication(for: url) else {
                    return .none
                }

                switch registryAuthentication.type {
                case .basic:
                    let authorizationString = "\(user):\(password)"
                    guard let authorizationData = authorizationString.data(using: .utf8) else {
                        return nil
                    }
                    return "Basic \(authorizationData.base64EncodedString())"
                case .token: // `user` value is irrelevant in this case
                    return "Bearer \(password)"
                }
            }
        } else {
            self.authorizationProvider = .none
        }

        self.httpClient = customHTTPClient ?? LegacyHTTPClient()
        self.archiverProvider = customArchiverProvider ?? { fileSystem in ZipArchiver(fileSystem: fileSystem) }
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.jsonDecoder = JSONDecoder.makeWithDefaults()
    }

    public var configured: Bool {
        !self.configuration.isEmpty
    }

    /// Cancel any outstanding requests
    public func cancel(deadline: DispatchTime) throws {
        try self.httpClient.cancel(deadline: deadline)
    }

    public func getPackageMetadata(
        package: PackageIdentity,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PackageMetadata, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(registryIdentity.scope)", "\(registryIdentity.name)")
        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
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
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                }.mapError {
                    RegistryError.failedRetrievingReleases($0)
                }
            )
        }
    }

    public func getPackageVersionMetadata(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PackageVersionMetadata, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(registryIdentity.scope)", "\(registryIdentity.name)", "\(version)")

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
                    switch response.statusCode {
                    case 200:
                        let versionMetadata = try response.parseJSON(
                            Serialization.VersionMetadata.self,
                            decoder: self.jsonDecoder
                        )

                        return PackageVersionMetadata(
                            registry: registry,
                            licenseURL: versionMetadata.metadata?.licenseURL.flatMap { URL(string: $0) },
                            readmeURL: versionMetadata.metadata?.readmeURL.flatMap { URL(string: $0) },
                            repositoryURLs: versionMetadata.metadata?.repositoryURLs?.compactMap { URL(string: $0) }
                        )
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                }.mapError {
                    RegistryError.failedRetrievingReleaseInfo($0)
                }
            )
        }
    }

    public func getAvailableManifests(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<[String: (toolsVersion: ToolsVersion, content: String?)], Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents(
            "\(registryIdentity.scope)",
            "\(registryIdentity.name)",
            "\(version)",
            Manifest.filename
        )

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .swift),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
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

                        var result = [String: (toolsVersion: ToolsVersion, content: String?)]()
                        let toolsVersion = try ToolsVersionParser.parse(utf8String: manifestContent)
                        result[Manifest.filename] = (toolsVersion: toolsVersion, content: manifestContent)

                        let alternativeManifests = try response.headers.parseManifestLinks()
                        for alternativeManifest in alternativeManifests {
                            result[alternativeManifest.filename] = (
                                toolsVersion: alternativeManifest.toolsVersion,
                                content: .none
                            )
                        }
                        return result
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                }.mapError {
                    RegistryError.failedRetrievingManifest($0)
                }
            )
        }
    }

    public func getManifestContent(
        package: PackageIdentity,
        version: Version,
        customToolsVersion: ToolsVersion?,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents(
            "\(registryIdentity.scope)",
            "\(registryIdentity.name)",
            "\(version)",
            "Package.swift"
        )

        if let toolsVersion = customToolsVersion {
            components.queryItems = [
                URLQueryItem(name: "swift-version", value: toolsVersion.description),
            ]
        }

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .swift),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response -> String in
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

                        return manifestContent
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                }.mapError {
                    RegistryError.failedRetrievingManifest($0)
                }
            )
        }
    }

    public func fetchSourceArchiveChecksum(
        package: PackageIdentity,
        version: Version,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(registryIdentity.scope)", "\(registryIdentity.name)", "\(version)")

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            switch result {
            case .success(let response):
                do {
                    switch response.statusCode {
                    case 200:
                        let versionMetadata = try response.parseJSON(
                            Serialization.VersionMetadata.self,
                            decoder: self.jsonDecoder
                        )
                        guard let sourceArchive = versionMetadata.resources
                            .first(where: { $0.name == "source-archive" })
                        else {
                            throw RegistryError.missingSourceArchive
                        }

                        guard let checksum = sourceArchive.checksum else {
                            throw RegistryError.invalidSourceArchive
                        }

                        if let fingerprintStorage = self.fingerprintStorage {
                            fingerprintStorage.put(
                                package: package,
                                version: version,
                                fingerprint: .init(origin: .registry(registry.url), value: checksum),
                                observabilityScope: observabilityScope,
                                callbackQueue: callbackQueue
                            ) { storageResult in
                                switch storageResult {
                                case .success:
                                    completion(.success(checksum))
                                case .failure(PackageFingerprintStorageError.conflict(_, let existing)):
                                    switch self.fingerprintCheckingMode {
                                    case .strict:
                                        completion(.failure(
                                            RegistryError
                                                .checksumChanged(latest: checksum, previous: existing.value)
                                        ))
                                    case .warn:
                                        observabilityScope
                                            .emit(
                                                warning: "The checksum \(checksum) from \(registry.url.absoluteString) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))"
                                            )
                                        completion(.success(checksum))
                                    }
                                case .failure(let error):
                                    completion(.failure(error))
                                }
                            }
                        } else {
                            completion(.success(checksum))
                        }
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                } catch {
                    completion(.failure(RegistryError.failedRetrievingReleaseChecksum(error)))
                }
            case .failure(let error):
                completion(.failure(RegistryError.failedRetrievingReleaseChecksum(error)))
            }
        }
    }

    public func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        checksumAlgorithm: HashAlgorithm, // the same algorithm used by `package compute-checksum` tool
        progressHandler: ((_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void)?,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = package.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(package)))
        }

        guard let registry = configuration.registry(for: registryIdentity.scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: registryIdentity.scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(registryIdentity.scope)", "\(registryIdentity.name)", "\(version).zip")

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        // prepare target download locations
        let downloadPath = destinationPath.withExtension("zip")
        do {
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
        } catch {
            return completion(.failure(error))
        }

        let request = LegacyHTTPClient.Request.download(
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .zip),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue),
            fileSystem: fileSystem,
            destination: downloadPath
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: progressHandler) { result in
            switch result {
            case .success(let response):
                do {
                    switch response.statusCode {
                    case 200:
                        try response.validateAPIVersion(isOptional: true)
                        try response.validateContentType(.zip)

                        withExpectedChecksum { result in
                            switch result {
                            case .success(let expectedChecksum):
                                do {
                                    let contents = try fileSystem.readFileContents(downloadPath)
                                    let actualChecksum = checksumAlgorithm.hash(contents).hexadecimalRepresentation

                                    if expectedChecksum != actualChecksum {
                                        switch self.fingerprintCheckingMode {
                                        case .strict:
                                            return completion(.failure(
                                                RegistryError
                                                    .invalidChecksum(expected: expectedChecksum, actual: actualChecksum)
                                            ))
                                        case .warn:
                                            observabilityScope
                                                .emit(
                                                    warning: "The checksum \(actualChecksum) does not match previously recorded value \(expectedChecksum)"
                                                )
                                        }
                                    }
                                    // validate that the destination does not already exist (again, as this is async)
                                    guard !fileSystem.exists(destinationPath) else {
                                        throw RegistryError.pathAlreadyExists(destinationPath)
                                    }
                                    try fileSystem.createDirectory(destinationPath, recursive: true)
                                    // extract the content
                                    let archiver = self.archiverProvider(fileSystem)
                                    // TODO: Bail if archive contains relative paths or overlapping files
                                    archiver.extract(from: downloadPath, to: destinationPath) { result in
                                        defer { try? fileSystem.removeFileTree(downloadPath) }
                                        completion(result.tryMap {
                                            // strip first level component
                                            try fileSystem.stripFirstLevel(of: destinationPath)
                                        }.mapError { error in
                                            StringError(
                                                "failed extracting '\(downloadPath)' to '\(destinationPath)': \(error)"
                                            )
                                        })
                                    }
                                } catch {
                                    completion(.failure(RegistryError.failedToComputeChecksum(error)))
                                }
                            case .failure(let error as RegistryError):
                                completion(.failure(error))
                            case .failure(let error):
                                completion(.failure(RegistryError.failedToDetermineExpectedChecksum(error)))
                            }
                        }
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                } catch {
                    completion(.failure(RegistryError.failedDownloadingSourceArchive(error)))
                }
            case .failure(let error):
                completion(.failure(RegistryError.failedDownloadingSourceArchive(error)))
            }
        }

        // We either use a previously recorded checksum, or fetch it from the registry
        func withExpectedChecksum(body: @escaping (Result<String, Error>) -> Void) {
            if let fingerprintStorage = self.fingerprintStorage {
                fingerprintStorage.get(
                    package: package,
                    version: version,
                    kind: .registry,
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue
                ) { result in
                    switch result {
                    case .success(let fingerprint):
                        body(.success(fingerprint.value))
                    case .failure(let error):
                        if error as? PackageFingerprintStorageError != .notFound {
                            observabilityScope
                                .emit(
                                    error: "Failed to get registry fingerprint for \(package) \(version) from storage: \(error)"
                                )
                        }
                        // Try fetching checksum from registry again no matter which kind of error it is
                        self.fetchSourceArchiveChecksum(
                            package: package,
                            version: version,
                            observabilityScope: observabilityScope,
                            callbackQueue: callbackQueue,
                            completion: body
                        )
                    }
                }
            } else {
                self.fetchSourceArchiveChecksum(
                    package: package,
                    version: version,
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue,
                    completion: body
                )
            }
        }
    }

    public func lookupIdentities(
        scmURL: URL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Set<PackageIdentity>, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registry = configuration.defaultRegistry else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: nil)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("identifiers")

        components.queryItems = [
            URLQueryItem(name: "url", value: scmURL.absoluteString),
        ]

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
                    switch response.statusCode {
                    case 200:
                        let packageIdentities = try response.parseJSON(
                            Serialization.PackageIdentifiers.self,
                            decoder: self.jsonDecoder
                        )
                        return Set(packageIdentities.identifiers.map {
                            PackageIdentity.plain($0)
                        })
                    case 404:
                        // 404 is valid, no identities mapped
                        return []
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200, 404])
                    }
                }.mapError {
                    RegistryError.failedIdentityLookup($0)
                }
            )
        }
    }

    public func login(
        url: URL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        let request = LegacyHTTPClient.Request(
            method: .post,
            url: url,
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
                    switch response.statusCode {
                    case 200:
                        return ()
                    default:
                        throw self.unexpectedStatusError(response, expectedStatus: [200])
                    }
                }
            )
        }
    }

    public func publish(
        registryURL: URL,
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageArchive: AbsolutePath,
        packageMetadata: AbsolutePath?,
        signature: Data?,
        timeout: DispatchTimeInterval? = .none,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PublishResult, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registryIdentity = packageIdentity.registry else {
            return completion(.failure(RegistryError.invalidPackageIdentity(packageIdentity)))
        }
        guard var components = URLComponents(url: registryURL, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registryURL)))
        }
        components.appendPathComponents(registryIdentity.scope.description)
        components.appendPathComponents(registryIdentity.name.description)
        components.appendPathComponents(packageVersion.description)

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registryURL)))
        }

        // TODO: don't load the entire file in memory
        guard let packageArchiveContent: Data = try? fileSystem.readFileContents(packageArchive) else {
            return completion(.failure(RegistryError.failedLoadingPackageArchive(packageArchive)))
        }
        var metadataContent: String? = .none
        if let packageMetadata = packageMetadata {
            do {
                metadataContent = try fileSystem.readFileContents(packageMetadata)
            } catch {
                return completion(.failure(RegistryError.failedLoadingPackageMetadata(packageMetadata)))
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

        // metadata field
        if let metadataContent = metadataContent {
            body.append(contentsOf: """
            \r
            --\(boundary)\r
            Content-Disposition: form-data; name=\"metadata\"\r
            Content-Type: application/json\r
            Content-Transfer-Encoding: quoted-printable\r
            \r
            \(metadataContent)
            """.utf8)
        }

        // footer
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        let request = LegacyHTTPClient.Request(
            method: .put,
            url: url,
            headers: [
                "Content-Type": "multipart/form-data;boundary=\"\(boundary)\"",
                "Accept": self.acceptHeader(mediaType: .json),
                "Expect": "100-continue",
                "Prefer": "respond-async",
            ],
            body: body,
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
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
                }.mapError {
                    RegistryError.failedPublishing($0)
                }
            )
        }
    }

    public func checkAvailability(
        registryURL: URL,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<AvailabilityStatus, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard var components = URLComponents(url: registryURL, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registryURL)))
        }
        components.appendPathComponents("availability")

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registryURL)))
        }

        let request = LegacyHTTPClient.Request(
            method: .get,
            url: url,
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(
                result.tryMap { response in
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
                }
            )
        }
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
        case 501:
            return RegistryError.authenticationMethodNotSupported
        default:
            return RegistryError.invalidResponseStatus(expected: expectedStatus, actual: response.statusCode)
        }
    }

    private func makeAsync<T>(
        _ closure: @escaping (Result<T, Error>) -> Void,
        on queue: DispatchQueue
    ) -> (Result<T, Error>) -> Void {
        { result in queue.async { closure(result) } }
    }

    private func defaultRequestOptions(
        timeout: DispatchTimeInterval? = .none,
        callbackQueue: DispatchQueue
    ) -> LegacyHTTPClient.Request.Options {
        var options = LegacyHTTPClient.Request.Options()
        options.timeout = timeout
        options.callbackQueue = callbackQueue
        options.authorizationProvider = self.authorizationProvider
        return options
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
    case failedToDetermineExpectedChecksum(Error)
    case failedToComputeChecksum(Error)
    case checksumChanged(latest: String, previous: String)
    case invalidChecksum(expected: String, actual: String)
    case pathAlreadyExists(AbsolutePath)
    case failedRetrievingReleases(Error)
    case failedRetrievingReleaseInfo(Error)
    case failedRetrievingReleaseChecksum(Error)
    case failedRetrievingManifest(Error)
    case failedDownloadingSourceArchive(Error)
    case failedIdentityLookup(Error)
    case failedLoadingPackageArchive(AbsolutePath)
    case failedLoadingPackageMetadata(AbsolutePath)
    case failedPublishing(Error)
    case missingPublishingLocation
    case serverError(code: Int, details: String)
    case unauthorized
    case authenticationMethodNotSupported
    case forbidden

    public var description: String {
        switch self {
        case .registryNotConfigured(let scope):
            if let scope = scope {
                return "No registry configured for '\(scope)' scope"
            } else {
                return "No registry configured'"
            }
        case .invalidPackageIdentity(let packageIdentity):
            return "Invalid package identifier '\(packageIdentity)'"
        case .invalidURL(let url):
            return "Invalid URL '\(url)'"
        case .invalidResponseStatus(let expected, let actual):
            return "Invalid registry response status '\(actual)', expected '\(expected)'"
        case .invalidContentVersion(let expected, let actual):
            return "Invalid registry response content version '\(actual ?? "")', expected '\(expected)'"
        case .invalidContentType(let expected, let actual):
            return "Invalid registry response content type '\(actual ?? "")', expected '\(expected)'"
        case .invalidResponse:
            return "Invalid registry response"
        case .missingSourceArchive:
            return "Missing registry source archive"
        case .invalidSourceArchive:
            return "Invalid registry source archive"
        case .unsupportedHashAlgorithm(let algorithm):
            return "Unsupported hash algorithm '\(algorithm)'"
        case .failedToDetermineExpectedChecksum(let error):
            return "Failed determining registry source archive checksum: \(error)"
        case .failedToComputeChecksum(let error):
            return "Failed computing registry source archive checksum: \(error)"
        case .checksumChanged(let latest, let previous):
            return "The latest checksum '\(latest)' is different from the previously recorded value '\(previous)'"
        case .invalidChecksum(let expected, let actual):
            return "Invalid registry source archive checksum '\(actual)', expected '\(expected)'"
        case .pathAlreadyExists(let path):
            return "Path already exists '\(path)'"
        case .failedRetrievingReleases(let error):
            return "Failed fetching releases from registry: \(error)"
        case .failedRetrievingReleaseInfo(let error):
            return "Failed fetching release information from registry: \(error)"
        case .failedRetrievingReleaseChecksum(let error):
            return "Failed fetching release checksum from registry: \(error)"
        case .failedRetrievingManifest(let error):
            return "Failed retrieving manifest from registry: \(error)"
        case .failedDownloadingSourceArchive(let error):
            return "Failed downloading source archive from registry: \(error)"
        case .failedIdentityLookup(let error):
            return "Failed looking up identity: \(error)"
        case .failedLoadingPackageArchive(let path):
            return "Failed loading package archive at '\(path)' for publishing"
        case .failedLoadingPackageMetadata(let path):
            return "Failed loading package metadata at '\(path)' for publishing"
        case .failedPublishing(let error):
            return "Failed publishing: \(error)"
        case .missingPublishingLocation:
            return "Response missing registry source archive"
        case .serverError(let code, let details):
            return "Server error \(code): \(details)"
        case .unauthorized:
            return "Missing or invalid authentication credentials"
        case .authenticationMethodNotSupported:
            return "Authentication method not supported"
        case .forbidden:
            return "Forbidden"
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
        "application/vnd.swift.registry.v\(self.apiVersion.rawValue)+\(mediaType)"
    }
}

extension RegistryClient {
    public struct PackageMetadata {
        public let registry: Registry
        public let versions: [Version]
        public let alternateLocations: [URL]?
    }

    public struct PackageVersionMetadata {
        public let registry: Registry
        public let licenseURL: URL?
        public let readmeURL: URL?
        public let repositoryURLs: [URL]?
    }
}

extension RegistryClient {
    fileprivate struct AlternativeLocationLink {
        let url: URL
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

        // internal for testing
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

        guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) }),
              let url = URL(string: link)
        else {
            return nil
        }

        guard let rel = fields.first(where: { $0.hasPrefix("rel=") }).flatMap({ parseLinkFieldValue($0) }),
              let kind = RegistryClient.AlternativeLocationLink.Kind(rawValue: rel)
        else {
            return nil
        }

        return RegistryClient.AlternativeLocationLink(
            url: url,
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

// marked public for cross module visibility
extension RegistryClient {
    public enum Serialization {
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

        // marked public for cross module visibility
        public struct VersionMetadata: Codable {
            public let id: String
            public let version: String
            public let resources: [Resource]
            public let metadata: AdditionalMetadata?

            public init(
                id: String,
                version: String,
                resources: [Resource],
                metadata: AdditionalMetadata?
            ) {
                self.id = id
                self.version = version
                self.resources = resources
                self.metadata = metadata
            }

            public struct Resource: Codable {
                public let name: String
                public let type: String
                public let checksum: String?

                public init(name: String, type: String, checksum: String) {
                    self.name = name
                    self.type = type
                    self.checksum = checksum
                }
            }

            public struct AdditionalMetadata: Codable {
                public let author: Author?
                public let description: String?
                public let licenseURL: String?
                public let readmeURL: String?
                public let repositoryURLs: [String]?

                public init(
                    author: Author? = nil,
                    description: String,
                    licenseURL: String? = nil,
                    readmeURL: String? = nil,
                    repositoryURLs: [String]? = nil
                ) {
                    self.author = author
                    self.description = description
                    self.licenseURL = licenseURL
                    self.readmeURL = readmeURL
                    self.repositoryURLs = repositoryURLs
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

        // marked public for cross module visibility
        public struct PackageIdentifiers: Codable {
            public let identifiers: [String]

            public init(identifiers: [String]) {
                self.identifiers = identifiers
            }
        }
    }
}

// MARK: - Utilities

extension AbsolutePath {
    fileprivate func withExtension(_ extension: String) -> AbsolutePath {
        guard !self.isRoot else { return self }
        let `extension` = `extension`.spm_dropPrefix(".")
        return self.parentDirectory.appending(component: "\(basename).\(`extension`)")
    }
}

extension URLComponents {
    fileprivate mutating func appendPathComponents(_ components: String...) {
        path += (path.last == "/" ? "" : "/") + components.joined(separator: "/")
    }
}
