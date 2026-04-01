//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import class TSCBasic.FileLock

/// Metadata about a source archive at a specific commit SHA.
public struct SourceArchiveMetadata: Codable, Sendable, Equatable {
    public var hasSubmodules: Bool

    public init(hasSubmodules: Bool) {
        self.hasSubmodules = hasSubmodules
    }

    private enum CodingKeys: String, CodingKey {
        case hasSubmodules = "has_submodules"
    }
}

/// A file-system-backed cache for source archive metadata keyed by (owner, repo, sha).
///
/// The cache stores files under:
/// ```
/// {basePath}/{owner}/{repo}/{sha}/
///     metadata.json
///     Package.swift
///     Package@swift-5.9.swift
/// ```
///
/// Content is immutable by SHA — once written, never invalidated. Reads are
/// lock-free since files are write-once. Writes use a per-repo file lock to
/// prevent races when multiple processes create SHA directories concurrently.
public final class SourceArchiveMetadataCache: Sendable {
    private let fileSystem: any FileSystem
    private let cachePath: AbsolutePath

    public init(fileSystem: any FileSystem, cachePath: AbsolutePath) {
        self.fileSystem = fileSystem
        self.cachePath = cachePath
    }

    public func getMetadata(owner: String, repo: String, sha: String) throws -> SourceArchiveMetadata? {
        let metadataPath = self.metadataFilePath(owner: owner, repo: repo, sha: sha)
        guard self.fileSystem.exists(metadataPath) else {
            return nil
        }
        let data: Data = try self.fileSystem.readFileContents(metadataPath)
        return try JSONDecoder().decode(SourceArchiveMetadata.self, from: data)
    }

    public func setMetadata(owner: String, repo: String, sha: String, metadata: SourceArchiveMetadata) throws {
        let directoryPath = self.shaDirectoryPath(owner: owner, repo: repo, sha: sha)
        let repoPath = self.cachePath.appending(components: owner, repo)
        try self.fileSystem.createDirectory(repoPath, recursive: true)
        try self.fileSystem.withLock(on: repoPath, type: .exclusive) {
            try self.fileSystem.createDirectory(directoryPath, recursive: true)
            let metadataPath = directoryPath.appending(component: "metadata.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metadata)
            try self.fileSystem.writeFileContents(metadataPath, data: data)
        }
    }

    public func getManifest(owner: String, repo: String, sha: String, filename: String) throws -> String? {
        let manifestPath = self.shaDirectoryPath(owner: owner, repo: repo, sha: sha)
            .appending(component: filename)
        guard self.fileSystem.exists(manifestPath) else {
            return nil
        }
        return try self.fileSystem.readFileContents(manifestPath) as String
    }

    public func setManifest(
        owner: String,
        repo: String,
        sha: String,
        filename: String,
        content: String
    ) throws {
        let directoryPath = self.shaDirectoryPath(owner: owner, repo: repo, sha: sha)
        let repoPath = self.cachePath.appending(components: owner, repo)
        try self.fileSystem.createDirectory(repoPath, recursive: true)
        try self.fileSystem.withLock(on: repoPath, type: .exclusive) {
            try self.fileSystem.createDirectory(directoryPath, recursive: true)
            let manifestPath = directoryPath.appending(component: filename)
            try self.fileSystem.writeFileContents(manifestPath, string: content)
        }
    }

    private func shaDirectoryPath(owner: String, repo: String, sha: String) -> AbsolutePath {
        self.cachePath.appending(components: owner, repo, sha)
    }

    private func metadataFilePath(owner: String, repo: String, sha: String) -> AbsolutePath {
        self.shaDirectoryPath(owner: owner, repo: repo, sha: sha).appending(component: "metadata.json")
    }
}
