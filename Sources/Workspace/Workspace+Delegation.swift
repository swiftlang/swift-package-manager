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

import struct Basics.AbsolutePath
import struct Basics.Diagnostic
import enum Dispatch.DispatchTimeInterval
import struct Foundation.URL
import class PackageLoading.ManifestLoader
import class PackageModel.Manifest
import struct PackageModel.PackageIdentity
import struct PackageModel.PackageReference
import struct PackageModel.Registry
import class PackageRegistry.RegistryClient
import class PackageRegistry.RegistryDownloadsManager
import class SourceControl.RepositoryManager
import struct SourceControl.RepositorySpecifier
import struct TSCUtility.Version

/// The delegate interface used by the workspace to report status information.
public protocol WorkspaceDelegate: AnyObject {
    /// The workspace is about to load a package manifest (which might be in the cache, or might need to be parsed).
    /// Note that this does not include speculative loading of manifests that may occur during
    /// dependency resolution; rather, it includes only the final manifest loading that happens after a particular
    /// package version has been checked out into a working directory.
    func willLoadManifest(
        packageIdentity: PackageIdentity,
        packagePath: AbsolutePath,
        url: String,
        version: Version?,
        packageKind: PackageReference.Kind
    )
    /// The workspace has loaded a package manifest, either successfully or not. The manifest is nil if an error occurs,
    /// in which case there will also be at least one error in the list of diagnostics (there may be warnings even if a
    /// manifest is loaded successfully).
    func didLoadManifest(
        packageIdentity: PackageIdentity,
        packagePath: AbsolutePath,
        url: String,
        version: Version?,
        packageKind: PackageReference.Kind,
        manifest: Manifest?,
        diagnostics: [Diagnostic],
        duration: DispatchTimeInterval
    )

    /// The workspace is about to compile a package manifest, as reported by the assigned manifest loader. this happens
    /// for non-cached manifests
    func willCompileManifest(packageIdentity: PackageIdentity, packageLocation: String)
    /// The workspace successfully compiled a package manifest, as reported by the assigned manifest loader. this
    /// happens for non-cached manifests
    func didCompileManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: DispatchTimeInterval)

    /// The workspace is about to evaluate (execute) a compiled package manifest, as reported by the assigned manifest
    /// loader. this happens for non-cached manifests
    func willEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String)
    /// The workspace successfully evaluated (executed) a compiled package manifest, as reported by the assigned
    /// manifest loader. this happens for non-cached manifests
    func didEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: DispatchTimeInterval)

    /// The workspace has started fetching this package.
    func willFetchPackage(package: PackageIdentity, packageLocation: String?, fetchDetails: PackageFetchDetails)
    /// The workspace has finished fetching this package.
    func didFetchPackage(
        package: PackageIdentity,
        packageLocation: String?,
        result: Result<PackageFetchDetails, Error>,
        duration: DispatchTimeInterval
    )
    /// Called every time the progress of the package fetch operation updates.
    func fetchingPackage(package: PackageIdentity, packageLocation: String?, progress: Int64, total: Int64?)

    /// The workspace has started updating this repository.
    func willUpdateRepository(package: PackageIdentity, repository url: String)
    /// The workspace has finished updating this repository.
    func didUpdateRepository(package: PackageIdentity, repository url: String, duration: DispatchTimeInterval)

    /// The workspace has finished updating and all the dependencies are already up-to-date.
    func dependenciesUpToDate()

    /// The workspace is about to clone a repository from the local cache to a working directory.
    func willCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath)
    /// The workspace has cloned a repository from the local cache to a working directory. The error indicates whether
    /// the operation failed or succeeded.
    func didCreateWorkingCopy(
        package: PackageIdentity,
        repository url: String,
        at path: AbsolutePath,
        duration: DispatchTimeInterval
    )

    /// The workspace is about to check out a particular revision of a working directory.
    func willCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath)
    /// The workspace has checked out a particular revision of a working directory. The error indicates whether the
    /// operation failed or succeeded.
    func didCheckOut(
        package: PackageIdentity,
        repository url: String,
        revision: String,
        at path: AbsolutePath,
        duration: DispatchTimeInterval
    )

    /// The workspace is removing this repository because it is no longer needed.
    func removing(package: PackageIdentity, packageLocation: String?)

    /// Called when the resolver is about to be run.
    func willResolveDependencies(reason: WorkspaceResolveReason)

    /// Called when the resolver begins to be compute the version for the repository.
    func willComputeVersion(package: PackageIdentity, location: String)
    /// Called when the resolver finished computing the version for the repository.
    func didComputeVersion(package: PackageIdentity, location: String, version: String, duration: DispatchTimeInterval)

    /// Called when the Package.resolved file is changed *outside* of libSwiftPM operations.
    ///
    /// This is only fired when activated using Workspace's watchResolvedFile() method.
    func resolvedFileChanged()

    /// The workspace has started downloading a binary artifact.
    func willDownloadBinaryArtifact(from url: String, fromCache: Bool)
    /// The workspace has finished downloading a binary artifact.
    func didDownloadBinaryArtifact(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    )
    /// The workspace is downloading a binary artifact.
    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?)
    /// The workspace finished downloading all binary artifacts.
    func didDownloadAllBinaryArtifacts()

    /// The workspace has started downloading a binary artifact.
    func willDownloadPrebuilt(from url: String, fromCache: Bool)
    /// The workspace has finished downloading a binary artifact.
    func didDownloadPrebuilt(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    )
    /// The workspace is downloading a binary artifact.
    func downloadingPrebuilt(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?)
    /// The workspace finished downloading all binary artifacts.
    func didDownloadAllPrebuilts()

    // handlers for unsigned and untrusted registry based dependencies
    func onUnsignedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version,
        completion: (Bool) -> Void
    )
    func onUntrustedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version,
        completion: (Bool) -> Void
    )

    /// The workspace has started updating dependencies
    func willUpdateDependencies()
    /// The workspace has finished updating dependencies
    func didUpdateDependencies(duration: DispatchTimeInterval)

    /// The workspace has started resolving dependencies
    func willResolveDependencies()
    /// The workspace has finished resolving dependencies
    func didResolveDependencies(duration: DispatchTimeInterval)

    /// The workspace has started loading the graph to memory
    func willLoadGraph()
    /// The workspace has finished loading the graph to memory
    func didLoadGraph(duration: DispatchTimeInterval)
}

// FIXME: default implementation until the feature is stable, at which point we should remove this and force the clients to implement
extension WorkspaceDelegate {
    public func onUnsignedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version,
        completion: (Bool) -> Void
    ) {
        // true == continue resolution
        // false == stop dependency resolution
        completion(true)
    }

    public func onUntrustedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version,
        completion: (Bool) -> Void
    ) {
        // true == continue resolution
        // false == stop dependency resolution
        completion(true)
    }
}

struct WorkspaceManifestLoaderDelegate: ManifestLoader.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func willLoad(packageIdentity: PackageIdentity, packageLocation: String, manifestPath: AbsolutePath) {
        // handled by workspace directly
    }

    func didLoad(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        // handled by workspace directly
    }

    func willParse(packageIdentity: PackageIdentity, packageLocation: String) {
        // noop
    }

    func didParse(packageIdentity: PackageIdentity, packageLocation: String, duration: DispatchTimeInterval) {
        // noop
    }

    func willCompile(packageIdentity: PackageIdentity, packageLocation: String, manifestPath: AbsolutePath) {
        self.workspaceDelegate?.willCompileManifest(packageIdentity: packageIdentity, packageLocation: packageLocation)
    }

    func didCompile(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didCompileManifest(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            duration: duration
        )
    }

    func willEvaluate(packageIdentity: PackageIdentity, packageLocation: String, manifestPath: AbsolutePath) {
        self.workspaceDelegate?.willCompileManifest(packageIdentity: packageIdentity, packageLocation: packageLocation)
    }

    func didEvaluate(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didEvaluateManifest(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            duration: duration
        )
    }
}

struct WorkspaceRepositoryManagerDelegate: RepositoryManager.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func willFetch(package: PackageIdentity, repository: RepositorySpecifier, details: RepositoryManager.FetchDetails) {
        self.workspaceDelegate?.willFetchPackage(
            package: package,
            packageLocation: repository.location.description,
            fetchDetails: PackageFetchDetails(fromCache: details.fromCache, updatedCache: details.updatedCache)
        )
    }

    func fetching(
        package: PackageIdentity,
        repository: RepositorySpecifier,
        objectsFetched: Int,
        totalObjectsToFetch: Int
    ) {
        self.workspaceDelegate?.fetchingPackage(
            package: package,
            packageLocation: repository.location.description,
            progress: Int64(objectsFetched),
            total: Int64(totalObjectsToFetch)
        )
    }

    func didFetch(
        package: PackageIdentity,
        repository: RepositorySpecifier,
        result: Result<RepositoryManager.FetchDetails, Error>,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didFetchPackage(
            package: package,
            packageLocation: repository.location.description,
            result: result.map { PackageFetchDetails(fromCache: $0.fromCache, updatedCache: $0.updatedCache) },
            duration: duration
        )
    }

    func willUpdate(package: PackageIdentity, repository: RepositorySpecifier) {
        self.workspaceDelegate?.willUpdateRepository(package: package, repository: repository.location.description)
    }

    func didUpdate(package: PackageIdentity, repository: RepositorySpecifier, duration: DispatchTimeInterval) {
        self.workspaceDelegate?.didUpdateRepository(
            package: package,
            repository: repository.location.description,
            duration: duration
        )
    }
}

struct WorkspaceRegistryDownloadsManagerDelegate: RegistryDownloadsManager.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func willFetch(package: PackageIdentity, version: Version, fetchDetails: RegistryDownloadsManager.FetchDetails) {
        self.workspaceDelegate?.willFetchPackage(
            package: package,
            packageLocation: .none,
            fetchDetails: PackageFetchDetails(
                fromCache: fetchDetails.fromCache,
                updatedCache: fetchDetails.updatedCache
            )
        )
    }

    func didFetch(
        package: PackageIdentity,
        version: Version,
        result: Result<RegistryDownloadsManager.FetchDetails, Error>,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didFetchPackage(
            package: package,
            packageLocation: .none,
            result: result.map { PackageFetchDetails(fromCache: $0.fromCache, updatedCache: $0.updatedCache) },
            duration: duration
        )
    }

    func fetching(package: PackageIdentity, version: Version, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        self.workspaceDelegate?.fetchingPackage(
            package: package,
            packageLocation: .none,
            progress: bytesDownloaded,
            total: totalBytesToDownload
        )
    }
}

struct WorkspaceRegistryClientDelegate: RegistryClient.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate?) {
        self.workspaceDelegate = workspaceDelegate
    }

    func onUnsigned(registry: Registry, package: PackageIdentity, version: Version, completion: (Bool) -> Void) {
        if let delegate = self.workspaceDelegate {
            delegate.onUnsignedRegistryPackage(
                registryURL: registry.url,
                package: package,
                version: version,
                completion: completion
            )
        } else {
            // true == continue resolution
            // false == stop dependency resolution
            completion(true)
        }
    }

    func onUntrusted(registry: Registry, package: PackageIdentity, version: Version, completion: (Bool) -> Void) {
        if let delegate = self.workspaceDelegate {
            delegate.onUntrustedRegistryPackage(
                registryURL: registry.url,
                package: package,
                version: version,
                completion: completion
            )
        } else {
            // true == continue resolution
            // false == stop dependency resolution
            completion(true)
        }
    }
}

struct WorkspaceBinaryArtifactsManagerDelegate: Workspace.BinaryArtifactsManager.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func willDownloadBinaryArtifact(from url: String, fromCache: Bool) {
        self.workspaceDelegate?.willDownloadBinaryArtifact(from: url, fromCache: fromCache)
    }

    func didDownloadBinaryArtifact(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didDownloadBinaryArtifact(from: url, result: result, duration: duration)
    }

    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        self.workspaceDelegate?.downloadingBinaryArtifact(
            from: url,
            bytesDownloaded: bytesDownloaded,
            totalBytesToDownload: totalBytesToDownload
        )
    }

    func didDownloadAllBinaryArtifacts() {
        self.workspaceDelegate?.didDownloadAllBinaryArtifacts()
    }
}

struct WorkspacePrebuiltsManagerDelegate: Workspace.PrebuiltsManager.Delegate {
    private weak var workspaceDelegate: Workspace.Delegate?

    init(workspaceDelegate: Workspace.Delegate) {
        self.workspaceDelegate = workspaceDelegate
    }

    func willDownloadPrebuilt(from url: String, fromCache: Bool) {
        self.workspaceDelegate?.willDownloadPrebuilt(from: url, fromCache: fromCache)
    }

    func didDownloadPrebuilt(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    ) {
        self.workspaceDelegate?.didDownloadPrebuilt(from: url, result: result, duration: duration)
    }

    func downloadingPrebuilt(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        self.workspaceDelegate?.downloadingPrebuilt(
            from: url,
            bytesDownloaded: bytesDownloaded,
            totalBytesToDownload: totalBytesToDownload
        )
    }

    func didDownloadAllPrebuilts() {
        self.workspaceDelegate?.didDownloadAllPrebuilts()
    }
}
