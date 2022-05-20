//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
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

/// Package registry client.
/// API specification: https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md
public final class RegistryClient: Cancellable {
    private let apiVersion: APIVersion = .v1

    private let configuration: RegistryConfiguration
    private let archiverProvider: (FileSystem) -> Archiver
    private let httpClient: HTTPClient
    private let authorizationProvider: HTTPClientAuthorizationProvider?
    private let fingerprintStorage: PackageFingerprintStorage?
    private let fingerprintCheckingMode: FingerprintCheckingMode
    private let jsonDecoder: JSONDecoder

    public init(
        configuration: RegistryConfiguration,
        fingerprintStorage: PackageFingerprintStorage?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        authorizationProvider: HTTPClientAuthorizationProvider? = .none,
        customHTTPClient: HTTPClient? = .none,
        customArchiverProvider: ((FileSystem) -> Archiver)? = .none
    ) {
        self.configuration = configuration
        self.authorizationProvider = authorizationProvider
        self.httpClient = customHTTPClient ?? HTTPClient()
        self.archiverProvider = customArchiverProvider ?? { fileSystem in ZipArchiver(fileSystem: fileSystem) }
        self.fingerprintStorage = fingerprintStorage
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.jsonDecoder = JSONDecoder.makeWithDefaults()
    }

    public var configured: Bool {
        return !self.configuration.isEmpty
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

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(scope)", "\(name)")
        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = HTTPClient.Request(
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
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .json)

                    guard let data = response.body else {
                        throw RegistryError.invalidResponse
                    }

                    let packageMetadata = try self.jsonDecoder.decode(Serialization.PackageMetadata.self, from: data)
                    let versions = packageMetadata.releases.filter { $0.value.problem == nil }
                        .compactMap { Version($0.key) }
                        .sorted(by: >)

                    let alternateLocations = try response.headers.parseAlternativeLocationLinks()

                    return PackageMetadata(
                        versions: versions,
                        alternateLocations: alternateLocations?.map{ $0.url }
                    )
                }.mapError {
                    RegistryError.failedRetrievingReleases($0)
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

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(scope)", "\(name)", "\(version)", Manifest.filename)

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = HTTPClient.Request(
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
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .swift)

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
                        result[alternativeManifest.filename] = (toolsVersion: alternativeManifest.toolsVersion, content: .none)
                    }
                    return result
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

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(scope)", "\(name)", "\(version)", "Package.swift")

        if let toolsVersion = customToolsVersion {
            components.queryItems = [
                URLQueryItem(name: "swift-version", value: toolsVersion.description),
            ]
        }

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = HTTPClient.Request(
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
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .swift)

                    guard let data = response.body else {
                        throw RegistryError.invalidResponse
                    }
                    guard let manifestContent = String(data: data, encoding: .utf8) else {
                        throw RegistryError.invalidResponse
                    }

                    return manifestContent
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

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(scope)", "\(name)", "\(version)")

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = HTTPClient.Request(
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
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .json)

                    guard let data = response.body else {
                        throw RegistryError.invalidResponse
                    }

                    let versionMetadata = try self.jsonDecoder.decode(Serialization.VersionMetadata.self, from: data)
                    guard let sourceArchive = versionMetadata.resources.first(where: { $0.name == "source-archive" }) else {
                        throw RegistryError.missingSourceArchive
                    }

                    guard let checksum = sourceArchive.checksum else {
                        throw RegistryError.invalidSourceArchive
                    }

                    if let fingerprintStorage = self.fingerprintStorage {
                        fingerprintStorage.put(package: package,
                                               version: version,
                                               fingerprint: .init(origin: .registry(registry.url), value: checksum),
                                               observabilityScope: observabilityScope,
                                               callbackQueue: callbackQueue) { storageResult in
                            switch storageResult {
                            case .success:
                                completion(.success(checksum))
                            case .failure(PackageFingerprintStorageError.conflict(_, let existing)):
                                switch self.fingerprintCheckingMode {
                                case .strict:
                                    completion(.failure(RegistryError.checksumChanged(latest: checksum, previous: existing.value)))
                                case .warn:
                                    observabilityScope.emit(warning: "The checksum \(checksum) from \(registry.url.absoluteString) does not match previously recorded value \(existing.value) from \(String(describing: existing.origin.url?.absoluteString))")
                                    completion(.success(checksum))
                                }
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    } else {
                        completion(.success(checksum))
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

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        guard var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true) else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }
        components.appendPathComponents("\(scope)", "\(name)", "\(version).zip")

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

        let request = HTTPClient.Request.download(
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
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .zip)
                } catch {
                    return completion(.failure(RegistryError.failedDownloadingSourceArchive(error)))
                }

                withExpectedChecksum { result in
                    switch result {
                    case .success(let expectedChecksum):
                        do {
                            let contents = try fileSystem.readFileContents(downloadPath)
                            let actualChecksum = checksumAlgorithm.hash(contents).hexadecimalRepresentation

                            if expectedChecksum != actualChecksum {
                                switch self.fingerprintCheckingMode {
                                case .strict:
                                    return completion(.failure(RegistryError.invalidChecksum(expected: expectedChecksum, actual: actualChecksum)))
                                case .warn:
                                    observabilityScope.emit(warning: "The checksum \(actualChecksum) does not match previously recorded value \(expectedChecksum)")
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
                                    StringError("failed extracting '\(downloadPath)' to '\(destinationPath)': \(error)")
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
            case .failure(let error):
                completion(.failure(RegistryError.failedDownloadingSourceArchive(error)))
            }
        }

        // We either use a previously recorded checksum, or fetch it from the registry
        func withExpectedChecksum(body: @escaping (Result<String, Error>) -> Void) {
            if let fingerprintStorage = self.fingerprintStorage {
                fingerprintStorage.get(package: package,
                                       version: version,
                                       kind: .registry,
                                       observabilityScope: observabilityScope,
                                       callbackQueue: callbackQueue) { result in
                    switch result {
                    case .success(let fingerprint):
                        body(.success(fingerprint.value))
                    case .failure(let error):
                        if error as? PackageFingerprintStorageError != .notFound {
                            observabilityScope.emit(error: "Failed to get registry fingerprint for \(package) \(version) from storage: \(error)")
                        }
                        // Try fetching checksum from registry again no matter which kind of error it is
                        self.fetchSourceArchiveChecksum(package: package,
                                                        version: version,
                                                        observabilityScope: observabilityScope,
                                                        callbackQueue: callbackQueue,
                                                        completion: body)
                    }
                }
            } else {
                self.fetchSourceArchiveChecksum(package: package,
                                                version: version,
                                                observabilityScope: observabilityScope,
                                                callbackQueue: callbackQueue,
                                                completion: body)
            }
        }
    }

    public func lookupIdentities(
        url: URL,
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
            URLQueryItem(name: "url", value: url.absoluteString),
        ]

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL(registry.url)))
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ],
            options: self.defaultRequestOptions(timeout: timeout, callbackQueue: callbackQueue)
        )

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(result.tryMap { response in
                try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .json)

                guard let data = response.body else {
                    throw RegistryError.invalidResponse
                }

                let packageIdentities = try self.jsonDecoder.decode(Serialization.PackageIdentifiers.self, from: data)
                return Set(packageIdentities.identifiers.map {
                    return PackageIdentity.plain($0)
                })
            })
        }
    }

    private func makeAsync<T>(_ closure: @escaping (Result<T, Error>) -> Void, on queue: DispatchQueue) -> (Result<T, Error>) -> Void {
        { result in queue.async { closure(result) } }
    }

    private func defaultRequestOptions(
        timeout: DispatchTimeInterval? = .none,
        callbackQueue: DispatchQueue
    ) -> HTTPClient.Request.Options {
        var options = HTTPClient.Request.Options()
        options.timeout = timeout
        options.callbackQueue = callbackQueue
        options.authorizationProvider = self.authorizationProvider
        return options
    }
}

public enum RegistryError: Error, CustomStringConvertible {
    case registryNotConfigured(scope: PackageIdentity.Scope?)
    case invalidPackage(PackageIdentity)
    case invalidURL(URL)
    case invalidResponseStatus(expected: Int, actual: Int)
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
    case failedRetrievingReleaseChecksum(Error)
    case failedRetrievingManifest(Error)
    case failedDownloadingSourceArchive(Error)

    public var description: String {
        switch self {
        case .registryNotConfigured(let scope):
            if let scope = scope {
                return "No registry configured for '\(scope)' scope"
            } else {
                return "No registry configured'"
            }
        case .invalidPackage(let package):
            return "Invalid package '\(package)'"
        case .invalidURL(let url):
            return "Invalid URL '\(url)'"
        case .invalidResponseStatus(let expected, let actual):
            return "Invalid registry response status '\(actual)', expected '\(expected)'"
        case .invalidContentVersion(expected: let expected, actual: let actual):
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
        case .failedRetrievingReleaseChecksum(let error):
            return "Failed fetching release checksum from registry: \(error)"
        case .failedRetrievingManifest(let error):
            return "Failed retrieving manifest from registry: \(error)"
        case .failedDownloadingSourceArchive(let error):
            return "Failed downloading source archive from registry: \(error)"
        }
    }
}

fileprivate extension RegistryClient {
    enum APIVersion: String {
        case v1 = "1"
    }
}

fileprivate extension RegistryClient {
    enum MediaType: String {
        case json
        case swift
        case zip
    }

    enum ContentType: String {
        case json = "application/json"
        case swift = "text/x-swift"
        case zip = "application/zip"
    }

    func acceptHeader(mediaType: MediaType) -> String {
        "application/vnd.swift.registry.v\(self.apiVersion.rawValue)+\(mediaType)"
    }

    func checkResponseStatusAndHeaders(_ response: HTTPClient.Response, expectedStatusCode: Int, expectedContentType: ContentType) throws {
        guard response.statusCode == expectedStatusCode else {
            throw RegistryError.invalidResponseStatus(expected: expectedStatusCode, actual: response.statusCode)
        }

        let contentVersion = response.headers.get("Content-Version").first
        guard contentVersion == self.apiVersion.rawValue else {
            throw RegistryError.invalidContentVersion(expected: self.apiVersion.rawValue, actual: contentVersion)
        }

        let contentType = response.headers.get("Content-Type").first
        guard contentType?.hasPrefix(expectedContentType.rawValue) == true else {
            throw RegistryError.invalidContentType(expected: expectedContentType.rawValue, actual: contentType)
        }
    }
}

extension RegistryClient {
    public struct PackageMetadata {
        public let versions: [Version]
        public let alternateLocations: [URL]?
    }
}

fileprivate extension RegistryClient {
    struct AlternativeLocationLink {
        let url: URL
        let kind: Kind

        enum Kind: String {
            case canonical
            case alternate
        }
    }
}

fileprivate extension RegistryClient {
    struct ManifestLink {
        let url: URL
        let filename: String
        let toolsVersion: ToolsVersion
    }
}

fileprivate extension HTTPClientHeaders {
    /*
    <https://github.com/mona/LinkedList>; rel="canonical",
    <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
     */
    func parseAlternativeLocationLinks() throws -> [RegistryClient.AlternativeLocationLink]? {
        return try self.get("Link").map { header -> [RegistryClient.AlternativeLocationLink] in
            let linkLines = header.split(separator: ",").map(String.init).map { $0.spm_chuzzle() ?? $0 }
            return try linkLines.compactMap { linkLine in
                try parseAlternativeLocationLine(linkLine)
            }
        }.flatMap{ $0 }
    }

    private func parseAlternativeLocationLine(_ value: String) throws -> RegistryClient.AlternativeLocationLink? {
        let fields = value.split(separator: ";")
            .map(String.init)
            .map { $0.spm_chuzzle() ?? $0 }

        guard fields.count == 2 else {
            return nil
        }

        guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) }), let url = URL(string: link) else {
            return nil
        }

        guard let rel = fields.first(where: { $0.hasPrefix("rel=") }).flatMap({ parseLinkFieldValue($0) }), let kind = RegistryClient.AlternativeLocationLink.Kind(rawValue: rel)  else {
            return nil
        }

        return RegistryClient.AlternativeLocationLink(
            url: url,
            kind: kind
        )
    }
}

fileprivate extension HTTPClientHeaders {
    /*
    <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0"
    */
    func parseManifestLinks() throws -> [RegistryClient.ManifestLink] {
        return try self.get("Link").map { header -> [RegistryClient.ManifestLink] in
            let linkLines = header.split(separator: ",").map(String.init).map { $0.spm_chuzzle() ?? $0 }
            return try linkLines.compactMap { linkLine in
                try parseManifestLinkLine(linkLine)
            }
        }.flatMap{ $0 }
    }

    private func parseManifestLinkLine(_ value: String) throws -> RegistryClient.ManifestLink? {
        let fields = value.split(separator: ";")
            .map(String.init)
            .map { $0.spm_chuzzle() ?? $0 }

        guard fields.count == 4 else {
            return nil
        }

        guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) }), let url = URL(string: link) else {
            return nil
        }

        guard let rel = fields.first(where: { $0.hasPrefix("rel=") }).flatMap({ parseLinkFieldValue($0) }), rel == "alternate" else {
            return nil
        }

        guard let filename = fields.first(where: { $0.hasPrefix("filename=") }).flatMap({ parseLinkFieldValue($0) }) else {
            return nil
        }

        guard let toolsVersion = fields.first(where: { $0.hasPrefix("swift-tools-version=") }).flatMap({ parseLinkFieldValue($0) }) else {
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

fileprivate extension HTTPClientHeaders {
     func parseLinkFieldValue(_ field: String) -> String? {
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
public extension RegistryClient {
    enum Serialization {
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
                public let description: String?

                public init(description: String) {
                    self.description = description
                }
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

fileprivate extension AbsolutePath {
    func withExtension(_ extension: String) -> AbsolutePath {
        guard !self.isRoot else { return self }
        let `extension` = `extension`.spm_dropPrefix(".")
        return self.parentDirectory.appending(component: "\(basename).\(`extension`)")
    }
}

fileprivate extension URLComponents {
    mutating func appendPathComponents(_ components: String...) {
        path += (path.last == "/" ? "" : "/") + components.joined(separator: "/")
    }
}
