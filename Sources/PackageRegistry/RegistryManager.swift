/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem

import TSCBasic
import TSCUtility

import Basics
import PackageLoading
import PackageModel

/// Package registry client.
/// API specification: https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md
public enum RegistryError: Error {
    case registryNotConfigured(scope: PackageIdentity.Scope?)
    case invalidPackage(PackageIdentity)
    case invalidURL
    case invalidResponseStatus(expected: Int, actual: Int)
    case invalidContentVersion(expected: String, actual: String?)
    case invalidContentType(expected: String, actual: String?)
    case invalidResponse
    case missingSourceArchive
    case invalidSourceArchive
    case unsupportedHashAlgorithm(String)
    case failedToDetermineExpectedChecksum(Error)
    case invalidChecksum(expected: String, actual: String)
}

public final class RegistryManager {
    private let apiVersion: APIVersion = .v1

    private let configuration: RegistryConfiguration
    private let identityResolver: IdentityResolver
    private let archiverFactory: (FileSystem) -> Archiver
    private let httpClient: HTTPClient
    private let authorizationProvider: HTTPClientAuthorizationProvider?

    public init(configuration: RegistryConfiguration,
                identityResolver: IdentityResolver,
                customArchiverFactory: ((FileSystem) -> Archiver)? = nil,
                customHTTPClient: HTTPClient? = nil,
                authorizationProvider: HTTPClientAuthorizationProvider? = nil)
    {
        self.configuration = configuration
        self.identityResolver = identityResolver
        self.archiverFactory = customArchiverFactory ?? { fileSystem in SourceArchiver(fileSystem: fileSystem) }
        self.httpClient = customHTTPClient ?? HTTPClient()
        self.authorizationProvider = authorizationProvider
    }

    public func fetchVersions(
        of package: PackageIdentity,
        timeout: DispatchTimeInterval? = nil,
        callbackQueue: DispatchQueue = .sharedConcurrent,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<[Version], Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("\(scope)", "\(name)")

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ]
        )
        request.options.timeout = timeout
        request.options.callbackQueue = callbackQueue
        request.options.authorizationProvider = authorizationProvider

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(result.tryMap { response in
                try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .json)

                guard let data = response.body,
                      case .dictionary(let payload) = try? JSON(data: data),
                      case .dictionary(let releases) = payload["releases"]
                else {
                    throw RegistryError.invalidResponse
                }

                let versions = releases.filter { (try? $0.value.getJSON("problem")) == nil }
                    .compactMap { Version($0.key) }
                    .sorted(by: >)
                return versions
            })
        }
    }

    public func fetchManifest(
        for version: Version,
        of package: PackageIdentity,
        using manifestLoader: ManifestLoaderProtocol,
        toolsVersion: ToolsVersion = .currentToolsVersion,
        swiftLanguageVersion: SwiftLanguageVersion? = nil,
        timeout: DispatchTimeInterval? = nil,
        callbackQueue: DispatchQueue = .sharedConcurrent,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("\(scope)", "\(name)", "\(version)", "Package.swift")

        if let swiftLanguageVersion = swiftLanguageVersion {
            components?.queryItems = [
                URLQueryItem(name: "swift-version", value: swiftLanguageVersion.rawValue),
            ]
        }

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .swift),
            ]
        )
        request.options.timeout = timeout
        request.options.callbackQueue = callbackQueue
        request.options.authorizationProvider = authorizationProvider

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            do {
                switch result {
                case .success(let response):
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .swift)

                    guard let data = response.body else {
                        throw RegistryError.invalidResponse
                    }

                    let fileSystem = InMemoryFileSystem()

                    let filename: String
                    if let swiftLanguageVersion = swiftLanguageVersion {
                        filename = Manifest.basename + "@swift-\(swiftLanguageVersion).swift"
                    } else {
                        filename = Manifest.basename + ".swift"
                    }

                    try fileSystem.writeFileContents(.root.appending(component: filename), bytes: ByteString(data))

                    // FIXME: this doesn't work for version-specific manifest
                    manifestLoader.load(
                        at: .root,
                        packageIdentity: package,
                        packageKind: .registry(package),
                        packageLocation: package.description, // FIXME: was originally PackageReference.locationString
                        version: version,
                        revision: nil,
                        toolsVersion: .currentToolsVersion,
                        identityResolver: self.identityResolver,
                        fileSystem: fileSystem,
                        observabilityScope: observabilityScope,
                        on: callbackQueue,
                        completion: completion
                    )
                case .failure(let error):
                    throw error
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func fetchSourceArchiveChecksum(
        for version: Version,
        of package: PackageIdentity,
        timeout: DispatchTimeInterval? = nil,
        callbackQueue: DispatchQueue = .sharedConcurrent,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("\(scope)", "\(name)", "\(version)")

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ]
        )
        request.options.timeout = timeout
        request.options.callbackQueue = callbackQueue
        request.options.authorizationProvider = authorizationProvider

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            completion(result.tryMap { response in
                try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .json)

                guard let data = response.body,
                      case .dictionary(let payload) = try? JSON(data: data),
                      case .array(let resources) = payload["resources"]
                else {
                    throw RegistryError.invalidResponse
                }

                guard let sourceArchive = resources.first(where: { (try? $0.get(String.self, forKey: "name")) == "source-archive" }) else {
                    throw RegistryError.missingSourceArchive
                }

                guard let checksum = try? sourceArchive.get(String.self, forKey: "checksum") else {
                    throw RegistryError.invalidSourceArchive
                }

                return checksum
            })
        }
    }

    public func downloadSourceArchive(
        for version: Version,
        of package: PackageIdentity,
        into fileSystem: FileSystem,
        at destinationPath: AbsolutePath,
        expectedChecksum: String? = nil, // previously recorded checksum, if any
        checksumAlgorithm: HashAlgorithm, // the same algorithm used by `package compute-checksum` tool
        timeout: DispatchTimeInterval? = nil,
        callbackQueue: DispatchQueue = .sharedConcurrent,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard case (let scope, let name)? = package.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        // We either use a previously recorded checksum, or fetch it from the registry
        func withExpectedChecksum(body: @escaping (Result<String, Error>) -> Void) {
            if let expectedChecksum = expectedChecksum {
                return body(.success(expectedChecksum))
            }
            self.fetchSourceArchiveChecksum(for: version, of: package, callbackQueue: callbackQueue, observabilityScope: observabilityScope, completion: body)
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("\(scope)", "\(name)", "\(version).zip")

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .zip),
            ]
        )
        request.options.timeout = timeout
        request.options.callbackQueue = callbackQueue
        request.options.authorizationProvider = authorizationProvider

        self.httpClient.execute(request, observabilityScope: observabilityScope, progress: nil) { result in
            switch result {
            case .success(let response):
                do {
                    try self.checkResponseStatusAndHeaders(response, expectedStatusCode: 200, expectedContentType: .zip)
                } catch {
                    return completion(.failure(error))
                }

                guard let data = response.body else {
                    return completion(.failure(RegistryError.invalidResponse))
                }
                let contents = ByteString(data)

                withExpectedChecksum { result in
                    switch result {
                    case .success(let expectedChecksum):
                        let actualChecksum = checksumAlgorithm.hash(contents).hexadecimalRepresentation
                        guard expectedChecksum == actualChecksum else {
                            return completion(.failure(RegistryError.invalidChecksum(expected: expectedChecksum, actual: actualChecksum)))
                        }

                        do {
                            try fileSystem.createDirectory(destinationPath, recursive: true)

                            let archivePath = destinationPath.withExtension("zip")
                            try fileSystem.writeFileContents(archivePath, bytes: contents)

                            let archiver = self.archiverFactory(fileSystem)
                            // TODO: Bail if archive contains relative paths or overlapping files
                            archiver.extract(from: archivePath, to: destinationPath) { result in
                                completion(result)
                                try? fileSystem.removeFileTree(archivePath)
                            }
                        } catch {
                            try? fileSystem.removeFileTree(destinationPath)
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        completion(.failure(RegistryError.failedToDetermineExpectedChecksum(error)))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func lookupIdentities(
        for url: Foundation.URL,
        timeout: DispatchTimeInterval? = nil,
        callbackQueue: DispatchQueue = .sharedConcurrent,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Set<PackageIdentity>, Error>) -> Void
    ) {
        let completion = self.makeAsync(completion, on: callbackQueue)

        guard let registry = configuration.defaultRegistry else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: nil)))
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("identifiers")

        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
        ]

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": self.acceptHeader(mediaType: .json),
            ]
        )
        request.options.timeout = timeout
        request.options.callbackQueue = callbackQueue
        request.options.authorizationProvider = authorizationProvider

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
}

public extension RegistryManager {
    enum APIVersion: String {
        case v1 = "1"
    }
}

private extension RegistryManager {
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
