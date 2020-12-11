/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
    case invalidOperation
    case invalidResponse
    case invalidURL
    case invalidChecksum(expected: String, actual: String)
}

public final class RegistryManager {
    internal static var archiverFactory: (FileSystem) -> Archiver = { fileSystem in
        return ZipArchiver(fileSystem: fileSystem)
    }

    internal static var clientFactory: (DiagnosticsEngine?) -> HTTPClientProtocol = { diagnosticEngine in
        var configuration = HTTPClientConfiguration()
        configuration.followRedirects = false

        return HTTPClient(configuration: configuration, handler: nil, diagnosticsEngine: diagnosticEngine)
    }

    private static var cache = ThreadSafeKeyValueStore<URL, RegistryManager>()

    private let registryBaseURL: Foundation.URL
    private let client: HTTPClientProtocol

    init(registryBaseURL: Foundation.URL, diagnosticEngine: DiagnosticsEngine? = nil) {
        self.registryBaseURL = registryBaseURL
        self.client = Self.clientFactory(diagnosticEngine)
    }

    public class func discover(
        for package: PackageReference,
        diagnosticsEngine: DiagnosticsEngine? = nil,
        on queue: DispatchQueue,
        completion: @escaping (Result<RegistryManager, Error>) -> Void
    ) {
        guard let url = URL(string: "https://\(package.identity)") else {
            return queue.async {
                completion(.failure(RegistryError.invalidURL))
            }
        }

        if let manager = cache[url] {
            queue.async {
                completion(.success(manager))
            }
        } else {
            let request = HTTPClient.Request(
                method: .head,
                url: url,
                headers: [
                    "Accept": "application/vnd.swift.registry.v1"
                ]
            )

            let client = clientFactory(diagnosticsEngine)
            client.execute(request) { result in
                switch result {
                case .success(let response):
                    if response.statusCode == 303,
                       response.headers.get("Content-Version").first == "1",
                       let location = response.headers.get("Location").first,
                       let redirectedURL = URL(string: location, relativeTo: url)
                    {
                        let manager = RegistryManager(registryBaseURL: redirectedURL, diagnosticEngine: diagnosticsEngine)
                        self.cache[url] = manager
                        queue.async {
                            completion(.success(manager))
                        }
                    } else {
                        queue.async {
                            completion(.failure(RegistryError.invalidResponse))
                        }
                    }
                case .failure(let error):
                    queue.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    public func fetchVersions(of package: PackageReference, completion: @escaping (Result<[Version], Error>) -> Void) {
        let request = HTTPClient.Request(
            method: .get,
            url: registryBaseURL,
            headers: [
                "Accept": "application/vnd.swift.registry.v1+json"
            ]
        )

        client.execute(request) { result in
            completion(result.tryMap { response in
                if response.statusCode == 200,
                   response.headers.get("Content-Version").first == "1",
                   response.headers.get("Content-Type").first?.hasPrefix("application/json") == true,
                   let data = response.body,
                   case .dictionary(let payload) = try? JSON(data: data),
                   case .dictionary(let releases) = payload["releases"]
                {
                    let versions = releases.filter { (try? $0.value.getJSON("problem")) == nil }
                        .compactMap { Version(string: $0.key) }
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
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        var components = URLComponents(url: registryBaseURL, resolvingAgainstBaseURL: true)!
        components.path += "/\(version)/Package.swift"
        if let swiftLanguageVersion = swiftLanguageVersion {
            components.queryItems = [
                URLQueryItem(name: "swift-version", value: swiftLanguageVersion.rawValue)
            ]
        }

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": "application/vnd.swift.registry.v1+swift"
            ]
        )

        client.execute(request) { result in
            completion(result.tryMap { response in
                if response.statusCode == 200,
                   response.headers.get("Content-Version").first == "1",
                   response.headers.get("Content-Type").first?.hasPrefix("text/x-swift") == true,
                   let data = response.body
                {
                    let contents = ByteString(data)
                    let manifest = try loadManifest(
                        contents,
                        baseURL: self.registryBaseURL,
                        manifestLoader: manifestLoader,
                        toolsVersion: toolsVersion,
                        swiftLanguageVersion: swiftLanguageVersion
                    )

                    return manifest
                } else {
                    throw RegistryError.invalidResponse
                }
            })
        }
    }

    public func downloadSourceArchive(
        for version: Version,
        of package: PackageReference,
        into fileSystem: FileSystem,
        at destinationPath: AbsolutePath,
        expectedChecksum: ByteString? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var components = URLComponents(url: registryBaseURL, resolvingAgainstBaseURL: true)!
        components.path += "/\(version).zip"

        guard let url = components.url else {
            return completion(.failure(RegistryError.invalidURL))
        }

        let request = HTTPClient.Request(
            method: .get,
            url: url,
            headers: [
                "Accept": "application/vnd.swift.registry.v1+zip"
            ]
        )

        client.execute(request) { result in
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
                        let actualChecksum = contents.sha256Checksum.hexadecimalRepresentation

                        guard (expectedChecksum?.hexadecimalRepresentation ?? actualChecksum) == actualChecksum,
                              advertisedChecksum == actualChecksum
                        else {
                            throw RegistryError.invalidChecksum(
                                expected: expectedChecksum?.hexadecimalRepresentation ?? advertisedChecksum,
                                actual: actualChecksum
                            )
                        }

                        let archivePath = destinationPath.withExtension("zip")
                        try fileSystem.writeFileContents(archivePath, bytes: contents)

                        try fileSystem.createDirectory(destinationPath, recursive: true)

                        let archiver = Self.archiverFactory(fileSystem)
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

private func loadManifest(
    _ contents: ByteString,
    baseURL: URL,
    manifestLoader: ManifestLoaderProtocol,
    toolsVersion: ToolsVersion,
    swiftLanguageVersion: SwiftLanguageVersion? = nil,
    packageKind: PackageReference.Kind = .local
) throws -> Manifest {
    let fs = InMemoryFileSystem()

    let filename: String
    if let swiftLanguageVersion = swiftLanguageVersion {
        filename = Manifest.basename + "@swift-\(swiftLanguageVersion).swift"
    } else {
        filename = Manifest.basename + ".swift"
    }

    try fs.writeFileContents(AbsolutePath.root.appending(component: filename), bytes: contents)
    return try manifestLoader.load(
        package: AbsolutePath.root,
        baseURL: baseURL.lastPathComponent,
        toolsVersion: toolsVersion,
        packageKind: packageKind,
        fileSystem: fs
    )
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

private extension ByteString {
    var sha256Checksum: ByteString {
        #if canImport(CryptoKit)
        if #available(macOS 10.15, *) {
            return CryptoKitSHA256().hash(self)
        }
        #endif

        return SHA256().hash(self)
    }
}
