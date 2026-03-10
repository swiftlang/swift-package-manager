//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SwiftPMInternal)
import Basics
import Foundation
import struct TSCBasic.ByteString

/// Errors related to Swift SDK alias resolution.
package enum SwiftSDKAliasError: Swift.Error, CustomStringConvertible {
    /// The requested alias was not found in the index.
    case aliasNotFound(String)

    /// No shard entry matches the current toolchain's compiler tag.
    case noMatchingToolchainVersion(alias: String, compilerTag: String)

    /// The alias remote could not be reached and no cached index is available.
    case aliasRemoteUnavailable(url: String, underlyingError: Swift.Error)

    /// The alias index file is malformed or has an unsupported schema version.
    case invalidAliasIndex(reason: String)

    /// The remote URL must use HTTPS.
    case httpsRemoteRequired(url: String)

    /// The shard file is empty or contains no valid entries.
    case emptyShard(alias: String)

    /// Could not determine the Swift compiler version tag for alias resolution.
    case unknownCompilerVersion

    package var description: String {
        switch self {
        case .aliasNotFound(let alias):
            var message = "No Swift SDK alias '\(alias)' found in the index."
            if alias.contains(".") {
                message += " If you intended to install from a local file, check that the path is correct."
            }
            message += " Use `swift sdk alias list` to see available aliases."
            return message
        case .noMatchingToolchainVersion(let alias, let compilerTag):
            return """
            No Swift SDK found for alias '\(alias)' matching compiler tag '\(compilerTag)'. \
            Check if a newer version of the SDK is available or update your toolchain.
            """
        case .aliasRemoteUnavailable(let url, let underlyingError):
            return """
            Could not fetch the Swift SDK alias index from '\(url)': \(underlyingError). \
            Check your network connection or try again later.
            """
        case .invalidAliasIndex(let reason):
            return "Invalid Swift SDK alias index: \(reason)"
        case .httpsRemoteRequired(let url):
            return "The remote URL '\(url)' is not valid. Swift SDK alias remotes must use HTTPS."
        case .emptyShard(let alias):
            return """
            The shard file for alias '\(alias)' is empty or contains no valid entries.
            """
        case .unknownCompilerVersion:
            return """
            Could not determine the Swift compiler version for alias resolution. \
            Ensure your toolchain is properly installed.
            """
        }
    }
}

/// Manages fetching, caching, and resolving Swift SDK aliases from a remote index.
package final class SwiftSDKAliasStore: Sendable {
    /// The currently supported major schema version for the alias index.
    static let supportedSchemaMajorVersion = 1

    /// Default remote URL for the official swift.org alias index.
    package static let defaultRemoteURL = "https://download.swift.org/swift-sdk-aliases"

    /// Filename for the top-level alias index.
    static let indexFilename = "aliases.json"

    /// Subdirectory within the Swift SDKs directory for alias data.
    static let aliasesSubdirectory = "aliases"

    /// Root directory for Swift SDK storage (e.g. ~/.swiftpm/swift-sdks/).
    private let swiftSDKsDirectory: AbsolutePath

    /// The filesystem to use for reading/writing cached files.
    private let fileSystem: any FileSystem

    /// Observability scope for logging.
    private let observabilityScope: ObservabilityScope

    /// The directory where alias data is cached.
    private var aliasesDirectory: AbsolutePath {
        swiftSDKsDirectory.appending(component: Self.aliasesSubdirectory)
    }

    /// Path to the cached index file.
    private var cachedIndexPath: AbsolutePath {
        aliasesDirectory.appending(component: Self.indexFilename)
    }

    package init(
        swiftSDKsDirectory: AbsolutePath,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.swiftSDKsDirectory = swiftSDKsDirectory
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
    }

    // MARK: - Index Operations

    /// Fetches the alias index from the remote, caching it locally.
    /// Falls back to the cached copy if the remote is unreachable.
    package func fetchIndex(httpClient: HTTPClient) async throws -> SwiftSDKAliasIndex {
        let remoteURL = try self.currentRemoteURL()

        do {
            let indexURL = URL(string: remoteURL + "/" + Self.indexFilename)
            guard let indexURL else {
                throw SwiftSDKAliasError.invalidAliasIndex(reason: "Invalid remote URL: \(remoteURL)")
            }

            let response = try await httpClient.getContent(indexURL)
            let index = try self.decodeAndValidateIndex(data: response)

            // Cache the fetched index atomically to avoid corruption from interrupted writes
            try self.ensureAliasesDirectoryExists()
            try self.fileSystem.writeFileContents(
                self.cachedIndexPath, bytes: .init(response), atomically: true
            )

            return index
        } catch let error as SwiftSDKAliasError {
            throw error
        } catch {
            // Try falling back to cache
            if self.fileSystem.isFile(self.cachedIndexPath) {
                self.observabilityScope.emit(
                    warning: "Could not fetch alias index from remote, using cached copy"
                )
                let cachedData: Data = try self.fileSystem.readFileContents(self.cachedIndexPath)
                return try self.decodeAndValidateIndex(data: cachedData)
            }

            throw SwiftSDKAliasError.aliasRemoteUnavailable(
                url: remoteURL,
                underlyingError: error
            )
        }
    }

    /// Resolves an alias to a specific Swift SDK for the given compiler tag.
    package func resolve(
        alias: String,
        swiftCompilerTag: String,
        httpClient: HTTPClient
    ) async throws -> ResolvedSwiftSDKAlias {
        let index = try await self.fetchIndex(httpClient: httpClient)

        guard let shardFilename = index.aliases[alias] else {
            throw SwiftSDKAliasError.aliasNotFound(alias)
        }

        let entries = try await self.fetchShard(
            filename: shardFilename,
            alias: alias,
            remoteURL: try self.currentRemoteURL(),
            httpClient: httpClient
        )

        guard let match = entries.first(where: { $0.swiftCompilerTag == swiftCompilerTag }) else {
            throw SwiftSDKAliasError.noMatchingToolchainVersion(
                alias: alias,
                compilerTag: swiftCompilerTag
            )
        }

        return ResolvedSwiftSDKAlias(
            url: match.url,
            checksum: match.checksum,
            id: match.id,
            targetTriple: match.targetTriple
        )
    }

    /// Returns the list of available alias names from the index, sorted alphabetically.
    package func listAliases(httpClient: HTTPClient) async throws -> [String] {
        let index = try await self.fetchIndex(httpClient: httpClient)
        return index.aliases.keys.sorted()
    }

    // MARK: - Remote Management

    /// Sets the remote URL for the alias index. The URL must use HTTPS.
    package func setRemote(_ url: String) throws(SwiftSDKAliasError) {
        guard url.hasPrefix("https://"), URL(string: url) != nil else {
            throw .httpsRemoteRequired(url: url)
        }

        do {
            try self.ensureAliasesDirectoryExists()

            // Read existing index or create a minimal one
            var index: SwiftSDKAliasIndex
            if self.fileSystem.isFile(self.cachedIndexPath) {
                let data: Data = try self.fileSystem.readFileContents(self.cachedIndexPath)
                index = try JSONDecoder.makeWithDefaults().decode(SwiftSDKAliasIndex.self, from: data)
            } else {
                index = SwiftSDKAliasIndex(
                    schemaVersion: "1.0",
                    aliases: [:]
                )
            }

            index.remote = url
            let encoder = JSONEncoder.makeWithDefaults(prettified: true)
            let data = try encoder.encode(index)
            try self.fileSystem.writeFileContents(
                self.cachedIndexPath, bytes: .init(data), atomically: true
            )
        } catch let error as SwiftSDKAliasError {
            throw error
        } catch {
            throw .invalidAliasIndex(reason: "Failed to update remote: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Returns the current remote URL, reading from cached index or using the default.
    private func currentRemoteURL() throws -> String {
        if self.fileSystem.isFile(self.cachedIndexPath) {
            let data: Data = try self.fileSystem.readFileContents(self.cachedIndexPath)
            let index = try JSONDecoder.makeWithDefaults().decode(SwiftSDKAliasIndex.self, from: data)
            if let remote = index.remote {
                return remote
            }
        }
        return Self.defaultRemoteURL
    }

    /// Fetches a JSONL shard file, caching it locally. Falls back to cache on network failure.
    private func fetchShard(
        filename: String,
        alias: String,
        remoteURL: String,
        httpClient: HTTPClient
    ) async throws -> [SwiftSDKAliasShardEntry] {
        // Validate shard filename to prevent path traversal
        guard !filename.contains("/"), !filename.contains("\\"), !filename.contains("..") else {
            throw SwiftSDKAliasError.invalidAliasIndex(
                reason: "Shard filename '\(filename)' contains path separators"
            )
        }

        let cachedShardPath = aliasesDirectory.appending(component: filename)

        do {
            let shardURL = URL(string: remoteURL + "/" + filename)
            guard let shardURL else {
                throw SwiftSDKAliasError.invalidAliasIndex(
                    reason: "Invalid shard URL: \(remoteURL)/\(filename)"
                )
            }

            let response = try await httpClient.getContent(shardURL)

            // Cache the shard
            try self.ensureAliasesDirectoryExists()
            try self.fileSystem.writeFileContents(
                cachedShardPath, bytes: .init(response), atomically: true
            )

            return try self.parseShardEntries(data: response, alias: alias)
        } catch let error as SwiftSDKAliasError {
            throw error
        } catch {
            // Try falling back to cache
            if self.fileSystem.isFile(cachedShardPath) {
                self.observabilityScope.emit(
                    warning: "Could not fetch shard '\(filename)' from remote, using cached copy"
                )
                let cachedData: Data = try self.fileSystem.readFileContents(cachedShardPath)
                return try self.parseShardEntries(data: cachedData, alias: alias)
            }

            throw SwiftSDKAliasError.aliasRemoteUnavailable(
                url: remoteURL + "/" + filename,
                underlyingError: error
            )
        }
    }

    /// Decodes and validates an alias index from raw data.
    private func decodeAndValidateIndex(data: Data) throws -> SwiftSDKAliasIndex {
        let decoder = JSONDecoder.makeWithDefaults()
        let index: SwiftSDKAliasIndex
        do {
            index = try decoder.decode(SwiftSDKAliasIndex.self, from: data)
        } catch {
            throw SwiftSDKAliasError.invalidAliasIndex(reason: "Failed to decode: \(error)")
        }

        // Accept any version with the same major version (e.g., "1.0", "1.1", "1.2")
        let versionComponents = index.schemaVersion.split(separator: ".")
        guard let majorString = versionComponents.first,
              let major = Int(majorString),
              major == Self.supportedSchemaMajorVersion else {
            throw SwiftSDKAliasError.invalidAliasIndex(
                reason: "Unsupported schema version '\(index.schemaVersion)', this tool supports version \(Self.supportedSchemaMajorVersion).x"
            )
        }

        return index
    }

    /// Parses JSONL shard data into an array of entries.
    /// Malformed lines are skipped with a warning.
    private func parseShardEntries(data: Data, alias: String) throws -> [SwiftSDKAliasShardEntry] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw SwiftSDKAliasError.emptyShard(alias: alias)
        }

        let decoder = JSONDecoder.makeWithDefaults()
        var entries: [SwiftSDKAliasShardEntry] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lineData = Data(trimmed.utf8)
            do {
                let entry = try decoder.decode(SwiftSDKAliasShardEntry.self, from: lineData)
                entries.append(entry)
            } catch {
                self.observabilityScope.emit(
                    warning: "Skipping malformed line in shard for alias '\(alias)': \(error)"
                )
            }
        }

        if entries.isEmpty {
            throw SwiftSDKAliasError.emptyShard(alias: alias)
        }

        return entries
    }

    /// Creates the aliases subdirectory if it doesn't already exist.
    private func ensureAliasesDirectoryExists() throws {
        if !self.fileSystem.isDirectory(aliasesDirectory) {
            try self.fileSystem.createDirectory(aliasesDirectory, recursive: true)
        }
    }
}

// MARK: - HTTPClient extension for fetching content

extension HTTPClient {
    /// Fetches the content at the given URL and returns it as raw Data.
    fileprivate func getContent(_ url: URL) async throws -> Data {
        let response = try await self.execute(.init(method: .get, url: url))
        guard response.statusCode == 200 else {
            throw StringError("HTTP \(response.statusCode) from \(url)")
        }
        guard let body = response.body else {
            throw StringError("Empty response body from \(url)")
        }
        return body
    }
}
