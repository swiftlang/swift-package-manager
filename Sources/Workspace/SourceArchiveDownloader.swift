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

import Basics
import Foundation
import PackageFingerprint
import PackageModel

import struct TSCBasic.ByteString
import protocol TSCBasic.HashAlgorithm
import struct TSCUtility.Version

/// Error thrown when a source archive checksum does not match the stored fingerprint.
public struct SourceArchiveChecksumMismatchError: Error, CustomStringConvertible {
    public let package: PackageIdentity
    public let version: Version
    public let expected: String
    public let actual: String

    public var description: String {
        "source archive checksum mismatch for \(package) \(version): expected '\(expected)', got '\(actual)'"
    }
}

/// Downloads, validates, and extracts source archives for git-hosted packages.
///
/// Implements simple checksum TOFU (trust on first use) via ``PackageFingerprintStorage``,
/// following the same cache-then-workspace flow used by ``RegistryDownloadsManager``.
public struct SourceArchiveDownloader: Sendable {
    private let httpClient: HTTPClient
    private let archiver: any Archiver
    private let fileSystem: any FileSystem

    public init(
        httpClient: HTTPClient,
        archiver: any Archiver,
        fileSystem: any FileSystem
    ) {
        self.httpClient = httpClient
        self.archiver = archiver
        self.fileSystem = fileSystem
    }

    /// Downloads, validates, and extracts a source archive.
    ///
    /// Follows the same cache-then-workspace flow as ``RegistryDownloadsManager``:
    /// workspace check, cache check, download, checksum TOFU, extract, cache, copy.
    ///
    /// - Returns: The SHA-256 checksum of the downloaded archive, or `nil` if the
    ///   content was already present on disk (cache hit or workspace hit).
    @discardableResult
    public func downloadSourceArchive(
        package: PackageIdentity,
        version: Version,
        archiveURL: URL,
        cachePath: AbsolutePath?,
        destinationPath: AbsolutePath,
        checksumAlgorithm: any HashAlgorithm,
        fingerprintStorage: (any PackageFingerprintStorage)?,
        fingerprintCheckingMode: FingerprintCheckingMode,
        sourceURL: SourceControlURL,
        authorizationProvider: (any AuthorizationProvider)?,
        progressHandler: (@Sendable (_ bytesReceived: Int64, _ totalBytes: Int64?) -> Void)?,
        observabilityScope: ObservabilityScope
    ) async throws -> String? {
        if self.fileSystem.exists(destinationPath.appending(component: Manifest.filename)) {
            return nil
        }

        if let cachePath, self.fileSystem.exists(cachePath.appending(component: Manifest.filename)) {
            try self.copyToDestination(from: cachePath, to: destinationPath)
            return nil
        }

        let tempDir = destinationPath.parentDirectory.appending(component: ".temp-\(UUID().uuidString)")
        let tempZipPath = tempDir.appending(component: "\(package)_\(version).zip")
        let extractPath = tempDir.appending(component: "extract")

        try self.fileSystem.createDirectory(tempDir, recursive: true)
        try self.fileSystem.createDirectory(extractPath, recursive: true)

        defer {
            try? self.fileSystem.removeFileTree(tempDir)
        }

        var options = HTTPClientRequest.Options()
        options.retryStrategy = .exponentialBackoff(maxAttempts: 3, baseDelay: .milliseconds(250))
        options.authorizationProvider = authorizationProvider?.httpAuthorizationHeader(for:)

        observabilityScope.emit(debug: "downloading \(package) \(version) source archive from \(archiveURL)")

        let response = try await self.httpClient.download(
            archiveURL,
            options: options,
            progressHandler: progressHandler,
            fileSystem: self.fileSystem,
            destination: tempZipPath
        )

        guard response.statusCode == 200 else {
            throw StringError(
                "failed downloading source archive from \(archiveURL): HTTP \(response.statusCode)"
            )
        }

        // TODO: expose Data based API on checksumAlgorithm
        let archiveContent: Data = try self.fileSystem.readFileContents(tempZipPath)
        let actualChecksum = checksumAlgorithm.hash(.init(archiveContent))
            .hexadecimalRepresentation

        if let fingerprintStorage {
            try self.validateFingerprint(
                package: package,
                version: version,
                checksum: actualChecksum,
                sourceURL: sourceURL,
                fingerprintStorage: fingerprintStorage,
                fingerprintCheckingMode: fingerprintCheckingMode,
                observabilityScope: observabilityScope
            )
        }

        try await self.archiver.extract(from: tempZipPath, to: extractPath)

        // GitHub archives wrap contents in a single top-level directory
        // (e.g. "repo-tag/"). Strip it if present. If the archive already
        // has Package.swift at the root, skip the strip.
        if !self.fileSystem.exists(extractPath.appending(component: Manifest.filename)) {
            try self.fileSystem.stripFirstLevel(of: extractPath)
        }

        try self.fileSystem.removeFileTree(tempZipPath)

        guard self.fileSystem.exists(extractPath.appending(component: Manifest.filename)) else {
            throw StringError(
                "source archive for \(package) \(version) does not contain a \(Manifest.filename) at the top level"
            )
        }

        // Cross-process lock on the cache path to prevent races when multiple
        // workspaces resolve the same dependency concurrently.
        if let cachePath {
            try self.fileSystem.withLock(on: cachePath, type: .exclusive) {
                guard !self.fileSystem.exists(cachePath.appending(component: Manifest.filename)) else {
                    return
                }
                if !self.fileSystem.exists(cachePath.parentDirectory) {
                    try self.fileSystem.createDirectory(cachePath.parentDirectory, recursive: true)
                }
                try self.fileSystem.copy(from: extractPath, to: cachePath)
            }
        }

        let source = cachePath ?? extractPath
        try self.copyToDestination(from: source, to: destinationPath)
        return actualChecksum
    }

    private func copyToDestination(from source: AbsolutePath, to destination: AbsolutePath) throws {
        if !self.fileSystem.exists(destination.parentDirectory) {
            try self.fileSystem.createDirectory(destination.parentDirectory, recursive: true)
        }
        try self.fileSystem.copy(from: source, to: destination)
    }

    private func validateFingerprint(
        package: PackageIdentity,
        version: Version,
        checksum: String,
        sourceURL: SourceControlURL,
        fingerprintStorage: any PackageFingerprintStorage,
        fingerprintCheckingMode: FingerprintCheckingMode,
        observabilityScope: ObservabilityScope
    ) throws {
        let newFingerprint = Fingerprint(
            origin: .sourceControl(sourceURL),
            value: checksum,
            contentType: .sourceArchive
        )

        do {
            let existing = try fingerprintStorage.get(
                package: package,
                version: version,
                kind: .sourceControl,
                contentType: .sourceArchive,
                observabilityScope: observabilityScope
            )

            if existing.value != checksum {
                let mismatch = SourceArchiveChecksumMismatchError(
                    package: package, version: version,
                    expected: existing.value, actual: checksum
                )
                switch fingerprintCheckingMode {
                case .strict:
                    throw mismatch
                case .warn:
                    observabilityScope.emit(warning: mismatch.description)
                }
            }
        } catch let error as PackageFingerprintStorageError where error == .notFound {
            try fingerprintStorage.put(
                package: package,
                version: version,
                fingerprint: newFingerprint,
                observabilityScope: observabilityScope
            )
        } catch let error as SourceArchiveChecksumMismatchError {
            throw error
        } catch {
            observabilityScope.emit(
                error: "failed to get source archive fingerprint for \(package) \(version)",
                underlyingError: error
            )
            throw error
        }
    }
}
