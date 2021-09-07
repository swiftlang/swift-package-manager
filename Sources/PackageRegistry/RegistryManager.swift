/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageLoading
import PackageModel

import TSCBasic
import TSCUtility

import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem

import Dispatch

public enum RegistryError: Error {
    case registryNotConfigured(scope: PackageIdentity.Scope)
    case invalidPackage(PackageReference)
    case invalidOperation
    case invalidResponse
    case invalidURL
    case invalidChecksum(expected: String, actual: String)
}

public final class RegistryManager {
    internal static var archiverFactory: (FileSystem) -> Archiver = { fileSystem in
        return SourceArchiver(fileSystem: fileSystem)
    }

    private static let sharedClient: HTTPClientProtocol = HTTPClient()

    var configuration: RegistryConfiguration
    var client: HTTPClientProtocol
    var identityResolver: IdentityResolver
    var authorizationProvider: HTTPClientAuthorizationProvider?
    var diagnosticEngine: DiagnosticsEngine?

    public init(configuration: RegistryConfiguration,
                identityResolver: IdentityResolver,
                authorizationProvider: HTTPClientAuthorizationProvider? = nil,
                diagnosticEngine: DiagnosticsEngine? = nil)
    {
        self.configuration = configuration
        self.client = Self.sharedClient
        self.identityResolver = identityResolver
        self.authorizationProvider = authorizationProvider
        self.diagnosticEngine = diagnosticEngine
    }

    public func fetchVersions(
        of package: PackageReference,
        on queue: DispatchQueue,
        completion: @escaping (Result<[Version], Error>) -> Void
    ) {
        guard case let (scope, name)? = package.identity.scopeAndName else {
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
                "Accept": "application/vnd.swift.registry.v1+json"
            ]
        )

        request.options.authorizationProvider = authorizationProvider

        client.execute(request, progress: nil) { result in
            completion(result.tryMap { response in
                if response.statusCode == 200,
                   response.headers.get("Content-Version").first == "1",
                   response.headers.get("Content-Type").first?.hasPrefix("application/json") == true,
                   let data = response.body,
                   case .dictionary(let payload) = try? JSON(data: data),
                   case .dictionary(let releases) = payload["releases"]
                {
                    let versions = releases.filter { (try? $0.value.getJSON("problem")) == nil }
                        .compactMap { Version($0.key) }
                        .sorted(by: >)
                    return versions
                } else {
                    throw RegistryError.invalidResponse
                }
            })
        }
    }

    public func fetchManifest(
        for version: Version,
        of package: PackageReference,
        using manifestLoader: ManifestLoaderProtocol,
        toolsVersion: ToolsVersion = .currentToolsVersion,
        swiftLanguageVersion: SwiftLanguageVersion? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        guard case let (scope, name)? = package.identity.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
        }

        var components = URLComponents(url: registry.url, resolvingAgainstBaseURL: true)
        components?.appendPathComponents("\(scope)", "\(name)", "\(version)", "Package.swift")
        if let swiftLanguageVersion = swiftLanguageVersion {
            components?.queryItems = [
                URLQueryItem(name: "swift-version", value: swiftLanguageVersion.rawValue)
            ]
        }

        guard let url = components?.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        var request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": "application/vnd.swift.registry.v1+swift"
            ]
        )

        request.options.authorizationProvider = authorizationProvider

        client.execute(request, progress: nil) { result in
            do {
                if case .failure(let error) = result {
                    throw error
                } else if case .success(let response) = result,
                   response.statusCode == 200,
                   response.headers.get("Content-Version").first == "1",
                   response.headers.get("Content-Type").first?.hasPrefix("text/x-swift") == true,
                   let data = response.body
                {
                    let fileSystem = InMemoryFileSystem()

                    let filename: String
                    if let swiftLanguageVersion = swiftLanguageVersion {
                        filename = Manifest.basename + "@swift-\(swiftLanguageVersion).swift"
                    } else {
                        filename = Manifest.basename + ".swift"
                    }

                    try fileSystem.writeFileContents(.root.appending(component: filename), bytes: ByteString(data))
                    manifestLoader.load(
                        at: .root,
                        packageIdentity: package.identity,
                        packageKind: .registry(package.identity),
                        packageLocation: package.location,
                        version: version,
                        revision: nil,
                        toolsVersion: .currentToolsVersion,
                        identityResolver: self.identityResolver,
                        fileSystem: fileSystem,
                        diagnostics: self.diagnosticEngine,
                        on: .sharedConcurrent,
                        completion: completion
                    )
                } else {
                    throw RegistryError.invalidResponse
                }
            } catch {
                queue.async {
                    completion(.failure(error))
                }
            }
        }
    }

    public func downloadSourceArchive(
        for version: Version,
        of package: PackageReference,
        into fileSystem: FileSystem,
        at destinationPath: AbsolutePath,
        expectedChecksum: ByteString? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard case let (scope, name)? = package.identity.scopeAndName else {
            return completion(.failure(RegistryError.invalidPackage(package)))
        }

        guard let registry = configuration.registry(for: scope) else {
            return completion(.failure(RegistryError.registryNotConfigured(scope: scope)))
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
                "Accept": "application/vnd.swift.registry.v1+zip"
            ]
        )

        request.options.authorizationProvider = authorizationProvider

        client.execute(request, progress: nil) { result in
            switch result {
            case .success(let response):
                if response.statusCode == 200,
                   response.headers.get("Content-Version").first == "1",
                   response.headers.get("Content-Type").first?.hasPrefix("application/zip") == true,
                   let digest = response.headers.get("Digest").first,
                   let data = response.body
                {
                    do {
                        let contents = ByteString(data)
                        let advertisedChecksum = digest.spm_dropPrefix("sha-256=")
                        let actualChecksum = SHA256().hash(contents).hexadecimalRepresentation

                        guard (expectedChecksum?.hexadecimalRepresentation ?? actualChecksum) == actualChecksum,
                              advertisedChecksum == actualChecksum
                        else {
                            throw RegistryError.invalidChecksum(
                                expected: expectedChecksum?.hexadecimalRepresentation ?? advertisedChecksum,
                                actual: actualChecksum
                            )
                        }

                        try fileSystem.createDirectory(destinationPath, recursive: true)

                        let archivePath = destinationPath.withExtension("zip")
                        try fileSystem.writeFileContents(archivePath, bytes: contents)

                        let archiver = Self.archiverFactory(fileSystem)
                        // TODO: Bail if archive contains relative paths or overlapping files
                        archiver.extract(from: archivePath, to: destinationPath) { result in
                            completion(result)
                            try? fileSystem.removeFileTree(archivePath)
                        }
                    } catch {
                        try? fileSystem.removeFileTree(destinationPath)
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(RegistryError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

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
