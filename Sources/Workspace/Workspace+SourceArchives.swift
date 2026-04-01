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

import struct Basics.AbsolutePath
import protocol Basics.Archiver
import class Basics.AsyncOperationQueue
import protocol Basics.AuthorizationProvider
import enum Basics.Concurrency
import struct Basics.GitHubSourceArchiveProvider
import class Basics.HTTPClient
import struct Basics.InternalError
import class Basics.ObservabilityScope
import struct Basics.RelativePath
import protocol Basics.SourceArchiveProvider
import struct Basics.SourceControlURL
import struct Basics.ZipArchiver
import func Basics.sourceArchiveProvider
import struct Dispatch.DispatchTime
import struct Foundation.UUID
import PackageFingerprint
import struct PackageModel.PackageIdentity
import struct PackageModel.PackageReference
import SourceControl
import struct TSCBasic.SHA256
import struct TSCBasic.StringError
import struct TSCUtility.Version

extension Workspace {

    /// Attempts to materialize a source archive for a versioned package.
    /// Returns the destination path if successful, `nil` if the package is
    /// not eligible or the download failed (caller should fall back to git).
    func materializeSourceArchive(
        package: PackageReference,
        version: Version,
        pinnedRevision: String? = nil,
        pinnedTag: String? = nil,
        container: SourceArchivePackageContainer? = nil,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath? {
        guard let container = container ?? self.makeSourceArchiveContainer(
            for: package, observabilityScope: observabilityScope
        ) else {
            return nil
        }
        do {
            let tag: String
            let revision: String
            if let pinnedTag, let pinnedRevision {
                tag = pinnedTag
                revision = pinnedRevision
            } else {
                guard let resolvedTag = try await container.getTag(for: version) else {
                    return nil
                }
                tag = resolvedTag
                let resolvedRevision = try await container.getRevision(forTag: tag)
                if let pinnedRevision, resolvedRevision != pinnedRevision {
                    observabilityScope.emit(
                        warning: "tag '\(tag)' for \(package.identity) \(version) resolved to \(resolvedRevision) " +
                                 "but Package.resolved pins \(pinnedRevision); falling back to git"
                    )
                    return nil
                }
                revision = resolvedRevision
            }
            let hasSubmodules = try await container.hasSubmodules(at: version)
            if hasSubmodules {
                return try await self.shallowClone(
                    package: package,
                    tag: tag,
                    revision: revision,
                    version: version,
                    observabilityScope: observabilityScope
                )
            } else {
                return try await self.downloadSourceArchive(
                    package: package,
                    at: version,
                    revision: revision,
                    tag: tag,
                    provider: container.provider,
                    downloader: self.makeSourceArchiveDownloader(),
                    observabilityScope: observabilityScope
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // In strict fingerprint checking mode, checksum mismatches must
            // fail resolution — not silently fall back to git.
            if error is SourceArchiveChecksumMismatchError,
               case .strict = FingerprintCheckingMode.map(self.configuration.fingerprintCheckingMode)
            {
                throw error
            }
            observabilityScope.emit(
                warning: "source archive download failed for \(package.identity), falling back to git: \(error)"
            )
            return nil
        }
    }

    /// Returns the appropriate authorization provider for the given source archive provider.
    func sourceArchiveAuthorizationProvider(
        for provider: any SourceArchiveProvider
    ) -> (any AuthorizationProvider)? {
        provider is GitHubSourceArchiveProvider
            ? GitHubSourceArchiveProvider.GitHubTokenAuthorizationProvider(
                underlying: self.authorizationProvider)
            : self.authorizationProvider
    }

    /// Creates a ``SourceArchiveDownloader`` using the workspace's shared HTTP client and file system.
    func makeSourceArchiveDownloader() -> SourceArchiveDownloader {
        SourceArchiveDownloader(
            httpClient: self.sourceArchiveHTTPClient,
            archiver: self.sourceArchiveArchiver ?? ZipArchiver(fileSystem: self.fileSystem),
            fileSystem: self.fileSystem
        )
    }

    /// Resolved paths for materializing a source archive dependency.
    private struct MaterializationPaths {
        let subpath: RelativePath
        let destinationPath: AbsolutePath
        let cachePath: AbsolutePath?
    }

    private func archivePaths(for identity: PackageIdentity, version: Version) throws -> MaterializationPaths {
        let subpath = try Basics.RelativePath(validating: identity.description)
            .appending(component: version.description)
        return MaterializationPaths(
            subpath: subpath,
            destinationPath: self.location.sourceArchiveDirectory.appending(subpath),
            cachePath: self.location.sharedSourceArchiveCacheDirectory.map { $0.appending(subpath) }
        )
    }

    private func shallowClonePaths(for identity: PackageIdentity, version: Version) throws -> MaterializationPaths {
        let subpath = try Basics.RelativePath(validating: identity.description)
            .appending(component: version.description)
        return MaterializationPaths(
            subpath: subpath,
            destinationPath: self.location.shallowCloneDirectory.appending(subpath),
            cachePath: self.location.sharedShallowCloneCacheDirectory.map { $0.appending(subpath) }
        )
    }

    /// Fetches content to `destinationPath` if not already present, calling
    /// delegate will/didFetchPackage around the fetch. Returns whether a
    /// fetch was performed (vs already-on-disk or cache hit).
    private func fetchIfNeeded(
        identity: PackageIdentity,
        packageLocation: String,
        paths: MaterializationPaths,
        fetch: () async throws -> Void,
        observabilityScope: ObservabilityScope
    ) async throws {
        let alreadyPresent = self.fileSystem.exists(paths.destinationPath.appending("Package.swift"))
        if alreadyPresent { return }

        if let cachePath = paths.cachePath,
           self.fileSystem.exists(cachePath.appending("Package.swift"))
        {
            self.delegate?.willFetchPackage(
                package: identity,
                packageLocation: packageLocation,
                fetchDetails: PackageFetchDetails(fromCache: true, updatedCache: false)
            )
            let fetchStart = DispatchTime.now()
            try self.fileSystem.createDirectory(paths.destinationPath.parentDirectory, recursive: true)
            try self.fileSystem.copy(from: cachePath, to: paths.destinationPath)
            self.delegate?.didFetchPackage(
                package: identity,
                packageLocation: packageLocation,
                result: .success(PackageFetchDetails(fromCache: true, updatedCache: false)),
                duration: fetchStart.distance(to: .now())
            )
            return
        }

        self.delegate?.willFetchPackage(
            package: identity,
            packageLocation: packageLocation,
            fetchDetails: PackageFetchDetails(fromCache: false, updatedCache: paths.cachePath != nil)
        )
        let fetchStart = DispatchTime.now()
        do {
            try await fetch()
        } catch {
            self.delegate?.didFetchPackage(
                package: identity,
                packageLocation: packageLocation,
                result: .failure(error),
                duration: fetchStart.distance(to: .now())
            )
            throw error
        }
        self.delegate?.didFetchPackage(
            package: identity,
            packageLocation: packageLocation,
            result: .success(PackageFetchDetails(fromCache: false, updatedCache: paths.cachePath != nil)),
            duration: fetchStart.distance(to: .now())
        )
    }

    /// Downloads a source archive for a package (ZIP path, no submodules).
    func downloadSourceArchive(
        package: PackageReference,
        at version: Version,
        revision: String,
        tag: String,
        provider: any SourceArchiveProvider,
        downloader: SourceArchiveDownloader,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        let paths = try archivePaths(for: package.identity, version: version)
        var downloadChecksum: String?

        try await fetchIfNeeded(
            identity: package.identity,
            packageLocation: package.locationString,
            paths: paths,
            fetch: {
                downloadChecksum = try await downloader.downloadSourceArchive(
                    package: package.identity,
                    version: version,
                    archiveURL: provider.archiveURL(for: tag),
                    cachePath: paths.cachePath,
                    destinationPath: paths.destinationPath,
                    checksumAlgorithm: SHA256(),
                    fingerprintStorage: self.fingerprints,
                    fingerprintCheckingMode: FingerprintCheckingMode.map(
                        self.configuration.fingerprintCheckingMode
                    ),
                    sourceURL: SourceControlURL(package.locationString),
                    authorizationProvider: self.sourceArchiveAuthorizationProvider(for: provider),
                    progressHandler: nil,
                    observabilityScope: observabilityScope
                )
            },
            observabilityScope: observabilityScope
        )

        // If the download was skipped (prefetch or cache hit), try to recover the
        // checksum from fingerprint storage so the managed state isn't left with nil.
        var checksum = downloadChecksum
        if checksum == nil, let fingerprints = self.fingerprints {
            checksum = try? fingerprints.get(
                package: package.identity,
                version: version,
                kind: .sourceControl,
                contentType: .sourceArchive,
                observabilityScope: observabilityScope
            ).value
        }

        let dependency = try ManagedDependency.sourceArchiveDownload(
            packageRef: package,
            state: SourceArchiveDownloadState(version: version, revision: revision, tag: tag, hasSubmodules: false, checksum: checksum),
            subpath: paths.subpath
        )
        await self.state.add(dependency: dependency)
        try await self.state.save()
        return paths.destinationPath
    }

    /// Performs a shallow clone for a package that has submodules.
    func shallowClone(
        package: PackageReference,
        tag: String,
        revision: String,
        version: Version,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        let paths = try shallowClonePaths(for: package.identity, version: version)

        try await fetchIfNeeded(
            identity: package.identity,
            packageLocation: package.locationString,
            paths: paths,
            fetch: {
                try await self.performShallowClone(
                    url: SourceControlURL(package.locationString),
                    tag: tag,
                    destinationPath: paths.destinationPath,
                    cachePath: paths.cachePath,
                    observabilityScope: observabilityScope
                )
            },
            observabilityScope: observabilityScope
        )

        let dependency = try ManagedDependency.sourceArchiveDownload(
            packageRef: package,
            state: SourceArchiveDownloadState(version: version, revision: revision, tag: tag, hasSubmodules: true, checksum: nil),
            subpath: paths.subpath
        )
        await self.state.add(dependency: dependency)
        try await self.state.save()
        return paths.destinationPath
    }

    /// Performs a shallow clone to `destinationPath`, using `cachePath` as
    /// an intermediate shared cache when available. Handles the
    /// temp-dir → lock → copy-to-cache → copy-to-destination flow.
    private func performShallowClone(
        url: SourceControlURL,
        tag: String,
        destinationPath: AbsolutePath,
        cachePath: AbsolutePath?,
        observabilityScope: ObservabilityScope
    ) async throws {
        guard let gitProvider = self.repositoryProvider as? GitRepositoryProvider else {
            throw InternalError("shallow clone requires GitRepositoryProvider")
        }
        let repository = RepositorySpecifier(url: url)

        if let cachePath {
            let tempClonePath = cachePath.parentDirectory.appending(
                component: ".temp-\(UUID().uuidString)")
            defer { try? self.fileSystem.removeFileTree(tempClonePath) }

            try await gitProvider.shallowClone(
                repository: repository, tag: tag, to: tempClonePath,
                recurseSubmodules: true
            )

            guard self.fileSystem.exists(tempClonePath.appending("Package.swift")) else {
                throw StringError("Package.swift not found in shallow clone at '\(tempClonePath)'")
            }

            try self.fileSystem.withLock(on: cachePath, type: .exclusive) {
                if !self.fileSystem.exists(cachePath.appending("Package.swift")) {
                    if !self.fileSystem.exists(cachePath.parentDirectory) {
                        try self.fileSystem.createDirectory(cachePath.parentDirectory, recursive: true)
                    }
                    try self.fileSystem.copy(from: tempClonePath, to: cachePath)
                }
            }

            try self.fileSystem.createDirectory(destinationPath.parentDirectory, recursive: true)
            try self.fileSystem.copy(from: cachePath, to: destinationPath)
        } else {
            do {
                try await gitProvider.shallowClone(
                    repository: repository, tag: tag, to: destinationPath,
                    recurseSubmodules: true
                )
                guard self.fileSystem.exists(destinationPath.appending("Package.swift")) else {
                    throw StringError("Package.swift not found in shallow clone at '\(destinationPath)'")
                }
            } catch {
                try? self.fileSystem.removeFileTree(destinationPath)
                throw error
            }
        }
    }

    /// Removes a source archive dependency from disk.
    func removeSourceArchive(for dependency: ManagedDependency) throws {
        let path = self.location.sourceArchiveSubdirectory(for: dependency)
        if self.fileSystem.exists(path) {
            try self.fileSystem.removeFileTree(path)
        }
    }

    /// Removes a shallow clone dependency from disk.
    func removeShallowClone(for dependency: ManagedDependency) throws {
        let path = self.location.shallowCloneSubdirectory(for: dependency)
        if self.fileSystem.exists(path) {
            try self.fileSystem.chmod(.userWritable, path: path, options: [.recursive, .onlyFiles])
            try self.fileSystem.removeFileTree(path)
        }
    }

    /// Returns whether a package is eligible for source archive fetching.
    ///
    /// A package qualifies when source archives are enabled in the workspace
    /// configuration and a ``SourceArchiveProvider`` exists for the package URL.
    func canUseSourceArchive(for package: PackageReference) -> Bool {
        guard self.configuration.useSourceArchives else { return false }
        guard case .remoteSourceControl(let url) = package.kind else { return false }
        return sourceArchiveProvider(for: SourceControlURL(url.absoluteString)) != nil
    }

    /// Pre-downloads source archive ZIPs concurrently for packages that need
    /// fetching. Called before the sequential materialization loop so that
    /// downloads happen in parallel — the loop then finds them on disk and
    /// only does state bookkeeping.
    func prefetchSourceArchives(
        for changes: [(PackageReference, PackageStateChange)],
        observabilityScope: ObservabilityScope
    ) async {
        let toFetch: [(package: PackageReference, version: Version)] = changes.compactMap { ref, state in
            switch state {
            case .added(let s), .updated(let s):
                guard case .version(let v) = s.requirement else { return nil }
                guard self.canUseSourceArchive(for: ref) else { return nil }
                return (ref, v)
            case .removed, .unchanged:
                return nil
            }
        }
        guard !toFetch.isEmpty else { return }

        let maxConcurrent = min(max(1, 3 * Concurrency.maxOperations / 4), 8)

        // Use AsyncOperationQueue instead of fixed batches so that a new
        // download starts as soon as any slot frees up, rather than waiting
        // for the entire batch to finish.
        let queue = AsyncOperationQueue(concurrentTasks: maxConcurrent)
        await withTaskGroup(of: Void.self) { group in
            for item in toFetch {
                group.addTask {
                    do {
                        _ = try await queue.withOperation {
                            await observabilityScope.makeChildScope(
                                description: "pre-downloading source archive",
                                metadata: item.package.diagnosticsMetadata
                            ).trap {
                                try await self.prefetchSingleArchive(
                                    package: item.package,
                                    version: item.version,
                                    observabilityScope: observabilityScope
                                )
                            }
                        }
                    } catch is CancellationError {
                        // Task was cancelled — nothing to report.
                    } catch {
                        observabilityScope.emit(
                            warning: "source archive prefetch queue error for \(item.package.identity): \(error)"
                        )
                    }
                }
            }
        }
    }

    /// Downloads a single source archive ZIP to the workspace destination,
    /// doing ONLY the HTTP download and extraction. No delegate calls, no
    /// state persistence — those happen in the sequential loop afterwards.
    private func prefetchSingleArchive(
        package: PackageReference,
        version: Version,
        observabilityScope: ObservabilityScope
    ) async throws {
        let identity = package.identity
        let archive = try archivePaths(for: identity, version: version)
        let clone = try shallowClonePaths(for: identity, version: version)

        // Fast path: check workspace and shared caches before any HTTP calls.
        for paths in [archive, clone] {
            if self.fileSystem.exists(paths.destinationPath.appending("Package.swift")) {
                return
            }
            if let cachePath = paths.cachePath,
               self.fileSystem.exists(cachePath.appending("Package.swift"))
            {
                try self.fileSystem.createDirectory(paths.destinationPath.parentDirectory, recursive: true)
                try self.fileSystem.copy(from: cachePath, to: paths.destinationPath)
                return
            }
        }

        guard let archiveContainer = self.makeSourceArchiveContainer(
            for: package, observabilityScope: observabilityScope
        ) else {
            return
        }
        guard let tag = try await archiveContainer.getTag(for: version) else {
            return
        }

        let hasSubmodules = try await archiveContainer.hasSubmodules(at: version)

        if hasSubmodules {
            try await self.performShallowClone(
                url: SourceControlURL(package.locationString),
                tag: tag,
                destinationPath: clone.destinationPath,
                cachePath: clone.cachePath,
                observabilityScope: observabilityScope
            )
        } else {
            let archiveURL = archiveContainer.provider.archiveURL(for: tag)
            try await self.makeSourceArchiveDownloader().downloadSourceArchive(
                package: identity,
                version: version,
                archiveURL: archiveURL,
                cachePath: archive.cachePath,
                destinationPath: archive.destinationPath,
                checksumAlgorithm: SHA256(),
                fingerprintStorage: self.fingerprints,
                fingerprintCheckingMode: FingerprintCheckingMode.map(
                    self.configuration.fingerprintCheckingMode
                ),
                sourceURL: SourceControlURL(package.locationString),
                authorizationProvider: self.sourceArchiveAuthorizationProvider(for: archiveContainer.provider),
                progressHandler: nil,
                observabilityScope: observabilityScope
            )
        }
    }
}
