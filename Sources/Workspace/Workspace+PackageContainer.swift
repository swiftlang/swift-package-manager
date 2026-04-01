//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import SourceControl
import TSCBasic

import class Basics.ObservabilityScope
import class Dispatch.DispatchQueue
import enum PackageFingerprint.FingerprintCheckingMode
import enum PackageGraph.ContainerUpdateStrategy
import protocol PackageGraph.PackageContainer
import protocol PackageGraph.PackageContainerProvider
import struct PackageModel.PackageReference

// MARK: - Package container provider

extension Workspace: PackageContainerProvider {
    public func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> any PackageContainer {
        switch package.kind {
        // If the container is local, just create and return a local package container.
        case .root, .fileSystem:
            let container = try FileSystemPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                fileSystem: self.fileSystem,
                observabilityScope: observabilityScope
            )
            return container
        // Resolve the container using source archives if eligible.
        // Skip the archive path for branch/revision-pinned packages — they
        // need git for revision-based queries and the archive probe would be wasted.
        case .remoteSourceControl
            where self.configuration.useSourceArchives
                && !self.isBranchOrRevisionPinned(package):
            if let archiveContainer = self.makeSourceArchiveContainer(
                for: package, observabilityScope: observabilityScope,
                gitContainerProvider: { [self] in
                    try await self.getSourceControlContainer(
                        for: package, updateStrategy: updateStrategy,
                        observabilityScope: observabilityScope
                    )
                }
            ) {
                // Validate we can actually fetch content via HTTPS for this repo.
                // Private repos where git ls-remote succeeds (SSH auth) but HTTPS
                // raw content returns 404 would cause slow resolution (1 failed HTTP
                // request per version probe). One quick manifest fetch catches this.
                // Try a few recent versions so one broken tag doesn't disable the
                // archive path for the entire package.
                do {
                    let versions = try await archiveContainer.versionsAscending()
                    guard !versions.isEmpty else {
                        throw StringError("no semver versions found")
                    }
                    var probeSucceeded = false
                    for candidate in versions.suffix(3).reversed() {
                        if let _ = try? await archiveContainer.toolsVersion(for: candidate) {
                            probeSucceeded = true
                            break
                        }
                    }
                    guard probeSucceeded else {
                        throw StringError("manifest fetch failed for recent versions")
                    }
                    return archiveContainer
                } catch {
                    observabilityScope.emit(
                        info: "source archive path unavailable for \(package.identity), using git: \(error)"
                    )
                }
            }
            // Fall through to standard git path if no provider matches
            fallthrough
        // Resolve the container using the repository manager.
        case .localSourceControl, .remoteSourceControl:
            let repositorySpecifier = try package.makeRepositorySpecifier()
            let handle = try await self.repositoryManager.lookup(
                package: package.identity,
                repository: repositorySpecifier,
                updateStrategy: updateStrategy.repositoryUpdateStrategy,
                observabilityScope: observabilityScope
            )

            // Open the repository.
            //
            // FIXME: Do we care about holding this open for the lifetime of the container.
            let repository = try await handle.open()
            let result = try SourceControlPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                repositorySpecifier: repositorySpecifier,
                repository: repository,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                fingerprintStorage: self.fingerprints,
                fingerprintCheckingMode: FingerprintCheckingMode
                    .map(self.configuration.fingerprintCheckingMode),
                observabilityScope: observabilityScope
            )
            return result
        // Resolve the container using the registry
        case .registry:
            let container = RegistryPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                registryClient: self.registryClient,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                observabilityScope: observabilityScope
            )
            return container
        }
    }

    /// Creates a ``SourceArchivePackageContainer`` for the given package
    /// without performing any validation probes. Returns `nil` if the package
    /// URL is not supported by any registered ``SourceArchiveProvider``.
    func makeSourceArchiveContainer(
        for package: PackageReference,
        observabilityScope: ObservabilityScope,
        gitContainerProvider: (@Sendable () async throws -> any PackageContainer)? = nil
    ) -> SourceArchivePackageContainer? {
        guard case .remoteSourceControl(let url) = package.kind else { return nil }
        guard let provider = Basics.sourceArchiveProvider(
            for: SourceControlURL(url.absoluteString)
        ) else { return nil }

        let metadataCachePath = self.location.sharedSourceArchiveMetadataCacheDirectory
            ?? self.location.scratchDirectory.appending(components: "source-archives", "metadata")
        let gitTagsProvider: (@Sendable (String) async throws -> String)?
        if let gitProvider = self.repositoryProvider as? GitRepositoryProvider {
            gitTagsProvider = { url in
                try await gitProvider.lsRemoteTags(for: RepositorySpecifier(url: SourceControlURL(url)))
            }
        } else {
            gitTagsProvider = nil
        }
        let resolver = SourceArchiveResolver(
            httpClient: self.sourceArchiveHTTPClient,
            authorizationProvider: self.sourceArchiveAuthorizationProvider(for: provider),
            gitTagsProvider: gitTagsProvider,
            tagMemoizer: self.sourceArchiveTagMemoizer
        )
        let metadataCache = SourceArchiveMetadataCache(
            fileSystem: self.fileSystem,
            cachePath: metadataCachePath
        )
        return SourceArchivePackageContainer(
            package: package,
            provider: provider,
            resolver: resolver,
            metadataCache: metadataCache,
            manifestLoader: self.manifestLoader,
            identityResolver: self.identityResolver,
            dependencyMapper: self.dependencyMapper,
            currentToolsVersion: self.currentToolsVersion,
            observabilityScope: observabilityScope,
            gitContainerProvider: gitContainerProvider
        )
    }

    /// Returns a ``SourceControlPackageContainer`` for the given package,
    /// bypassing source archive resolution. Used as a fallback when the source
    /// archive path fails for a specific dependency.
    func getSourceControlContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> SourceControlPackageContainer {
        let repositorySpecifier = try package.makeRepositorySpecifier()
        let handle = try await self.repositoryManager.lookup(
            package: package.identity,
            repository: repositorySpecifier,
            updateStrategy: updateStrategy.repositoryUpdateStrategy,
            observabilityScope: observabilityScope
        )
        let repository = try await handle.open()
        return try SourceControlPackageContainer(
            package: package,
            identityResolver: self.identityResolver,
            dependencyMapper: self.dependencyMapper,
            repositorySpecifier: repositorySpecifier,
            repository: repository,
            manifestLoader: self.manifestLoader,
            currentToolsVersion: self.currentToolsVersion,
            fingerprintStorage: self.fingerprints,
            fingerprintCheckingMode: FingerprintCheckingMode
                .map(self.configuration.fingerprintCheckingMode),
            observabilityScope: observabilityScope
        )
    }

    /// Returns true if the package is currently pinned to a branch or revision
    /// (not a version). These packages need git for resolution and the source
    /// archive probe would be wasted work.
    private func isBranchOrRevisionPinned(_ package: PackageReference) -> Bool {
        guard let store = try? self.resolvedPackagesStore.load() else {
            return false
        }
        guard let resolved = store.resolvedPackages[package.identity] else {
            return false
        }
        switch resolved.state {
        case .branch, .revision:
            return true
        case .version:
            return false
        }
    }
}
