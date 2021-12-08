/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import class Foundation.JSONDecoder
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
import PackageLoading
import PackageModel
import TSCBasic
import protocol TSCUtility.Archiver
import struct TSCUtility.ZipArchiver

/// Package registry client.
/// API specification: https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md
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

public final class RegistryClient {
    private let apiVersion: APIVersion = .v1

    private let configuration: RegistryConfiguration
    private let identityResolver: IdentityResolver
    private let archiverProvider: (FileSystem) -> Archiver
    private let httpClient: HTTPClient
    private let authorizationProvider: HTTPClientAuthorizationProvider?
    private let jsonDecoder: JSONDecoder

    public init(
        configuration: RegistryConfiguration,
        identityResolver: IdentityResolver,
        authorizationProvider: HTTPClientAuthorizationProvider? = .none,
        customHTTPClient: HTTPClient? = .none,
        customArchiverProvider: ((FileSystem) -> Archiver)? = .none
    ) {
        self.configuration = configuration
        self.identityResolver = identityResolver
        self.authorizationProvider = authorizationProvider
        self.httpClient = customHTTPClient ?? HTTPClient()
        self.archiverProvider = customArchiverProvider ?? { fileSystem in ZipArchiver(fileSystem: fileSystem) }
        self.jsonDecoder = JSONDecoder.makeWithDefaults()
    }

    public func fetchVersions(
        package: PackageIdentity,
        timeout: DispatchTimeInterval? = .none,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<[Version], Error>) -> Void
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
                    return versions
                }.mapError{
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
        completion: @escaping (Result<[String: ToolsVersion], Error>) -> Void
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

                    var result = [String: ToolsVersion]()
                    let toolsVersion = try ToolsVersionLoader().load(utf8String: manifestContent)
                    result[Manifest.filename] = toolsVersion

                    let alternativeManifests = try response.headers.get("Link").map { try parseLinkHeader($0) }.flatMap{ $0 }
                    for alternativeManifest in alternativeManifests {
                        result[alternativeManifest.filename] = alternativeManifest.toolsVersion
                    }
                    return result
                }.mapError{
                    RegistryError.failedRetrievingManifest($0)
                }
            )
        }

        func parseLinkHeader(_ value: String) throws -> [ManifestLink] {
            let linkLines = value.split(separator: ",").map(String.init).map{ $0.spm_chuzzle() ?? $0 }
            return try linkLines.compactMap { linkLine in
                try parseLinkLine(linkLine)
            }
        }

        // <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
        func parseLinkLine(_ value: String) throws -> ManifestLink? {
            let fields = value.split(separator: ";")
                .map(String.init)
                .map{ $0.spm_chuzzle() ?? $0 }

            guard fields.count == 4 else {
                return nil
            }

            guard let link = fields.first(where: { $0.hasPrefix("<") }).map({ String($0.dropFirst().dropLast()) }) else {
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

            return ManifestLink(
                value: link,
                filename: filename,
                toolsVersion: toolsVersion
            )
        }

        func parseLinkFieldValue(_ field: String) -> String? {
            let parts = field.split(separator: "=")
                .map(String.init)
                .map{ $0.spm_chuzzle() ?? $0 }

            guard parts.count == 2 else {
                return nil
            }

            return parts[1].replacingOccurrences(of: "\"", with: "")
        }

        struct ManifestLink {
            let value: String
            let filename: String
            let toolsVersion: ToolsVersion
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
                }.mapError{
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
            completion(
                result.tryMap { response in
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

                    return checksum
                }.mapError{
                    RegistryError.failedRetrievingReleaseChecksum($0)
                }
            )
        }
    }

    public func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        fileSystem: FileSystem,
        destinationPath: AbsolutePath,
        expectedChecksum: String?, // previously recorded checksum, if any
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
            try fileSystem.createDirectory(destinationPath, recursive: true)
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
                            guard expectedChecksum == actualChecksum else {
                                return completion(.failure(RegistryError.invalidChecksum(expected: expectedChecksum, actual: actualChecksum)))
                            }

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
            if let expectedChecksum = expectedChecksum {
                return body(.success(expectedChecksum))
            }
            self.fetchSourceArchiveChecksum(
                package: package,
                version: version,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                completion: body
            )
        }
    }

    public func lookupIdentities(
        url: Foundation.URL,
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

                guard let data = response.body,
                      case .dictionary(let payload) = try? JSON(data: data),
                      case .array(let identifiers) = payload["identifiers"]
                else {
                    throw RegistryError.invalidResponse
                }

                let packageIdentities: [PackageIdentity] = identifiers.compactMap {
                    guard case .string(let string) = $0 else {
                        return nil
                    }
                    return PackageIdentity.plain(string)
                }

                return Set(packageIdentities)
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

private extension RegistryClient {
    enum APIVersion: String {
        case v1 = "1"
    }
}

private extension RegistryClient {
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

// MARK: - Serialization

extension RegistryClient {
    public enum Serialization {

        public struct PackageMetadata: Codable {
            public var releases: [String: Release]

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

        public struct VersionMetadata: Codable {
            public var id: String
            public var version: String
            public var resources: [Resource]
            public var metadata: AdditionalMetadata

            public init(
                id: String,
                version: String,
                resources: [Resource],
                metadata: AdditionalMetadata
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
    }
}

// MARK: - Utilities

private extension String {
    /// Drops the given suffix from the string, if present.
    func spm_dropPrefix(_ prefix: String) -> String {
        if hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}

private extension AbsolutePath {
    func withExtension(_ extension: String) -> AbsolutePath {
        guard !self.isRoot else { return self }
        let `extension` = `extension`.spm_dropPrefix(".")
        return AbsolutePath(self, RelativePath("..")).appending(component: "\(basename).\(`extension`)")
    }
}

private extension URLComponents {
    mutating func appendPathComponents(_ components: String...) {
        path += (path.last == "/" ? "" : "/") + components.joined(separator: "/")
    }
}
