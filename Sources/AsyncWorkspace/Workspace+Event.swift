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

package import _Concurrency
package import struct Basics.AbsolutePath
private import struct Basics.Diagnostic
private import enum Basics.SendableTimeInterval
private import struct Basics.Version
package import struct Foundation.URL
private import class PackageModel.Manifest
package import struct PackageModel.PackageIdentity
private import struct PackageModel.PackageReference
package import struct Workspace.PackageFetchDetails
private import class Workspace.Workspace
internal import enum Workspace.WorkspaceResolveReason

extension Workspace {
    /// The events interface used by the workspace to report status information.
    package enum Event {
        /// The workspace is about to load a package manifest (which might be in the cache, or might need to be parsed).
        /// Note that this does not include speculative loading of manifests that may occur during
        /// dependency resolution; rather, it includes only the final manifest loading that happens after a particular
        /// package version has been checked out into a working directory.
        case willLoadManifest(
            packageIdentity: PackageIdentity,
            packagePath: AbsolutePath,
            url: String,
            version: Version?,
            packageKind: PackageReference.Kind
        )
        /// The workspace has loaded a package manifest, either successfully or not. The manifest is nil if an error occurs,
        /// in which case there will also be at least one error in the list of diagnostics (there may be warnings even if a
        /// manifest is loaded successfully).
        case didLoadManifest(
            packageIdentity: PackageIdentity,
            packagePath: AbsolutePath,
            url: String,
            version: Version?,
            packageKind: PackageReference.Kind,
            manifest: Manifest?,
            diagnostics: [Diagnostic],
            duration: SendableTimeInterval
        )

        /// The workspace is about to compile a package manifest, as reported by the assigned manifest loader. this happens
        /// for non-cached manifests
        case willCompileManifest(packageIdentity: PackageIdentity, packageLocation: String)
        /// The workspace successfully compiled a package manifest, as reported by the assigned manifest loader. this
        /// happens for non-cached manifests
        case didCompileManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: SendableTimeInterval)

        /// The workspace is about to evaluate (execute) a compiled package manifest, as reported by the assigned manifest
        /// loader. this happens for non-cached manifests
        case willEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String)
        /// The workspace successfully evaluated (executed) a compiled package manifest, as reported by the assigned
        /// manifest loader. this happens for non-cached manifests
        case didEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: SendableTimeInterval)

        /// The workspace has started fetching this package.
        case willFetchPackage(package: PackageIdentity, packageLocation: String?, fetchDetails: PackageFetchDetails)
        /// The workspace has finished fetching this package.
        case didFetchPackage(
            package: PackageIdentity,
            packageLocation: String?,
            result: Result<PackageFetchDetails, Error>,
            duration: SendableTimeInterval
        )
        /// Called every time the progress of the package fetch operation updates.
        case fetchingPackage(package: PackageIdentity, packageLocation: String?, progress: Int64, total: Int64?)

        /// The workspace has started updating this repository.
        case willUpdateRepository(package: PackageIdentity, repository: URL)
        /// The workspace has finished updating this repository.
        case didUpdateRepository(package: PackageIdentity, repository: URL, duration: SendableTimeInterval)

        /// The workspace has finished updating and all the dependencies are already up-to-date.
        case dependenciesUpToDate

        /// The workspace is about to clone a repository from the local cache to a working directory.
        case willCreateWorkingCopy(package: PackageIdentity, repository: URL, at: AbsolutePath)
        /// The workspace has cloned a repository from the local cache to a working directory. The error indicates whether
        /// the operation failed or succeeded.
        case didCreateWorkingCopy(
            package: PackageIdentity,
            repository: URL,
            at: AbsolutePath,
            duration: SendableTimeInterval
        )

        /// The workspace is about to check out a particular revision of a working directory.
        case willCheckOut(package: PackageIdentity, repository: URL, revision: String, at: AbsolutePath)
        /// The workspace has checked out a particular revision of a working directory. The error indicates whether the
        /// operation failed or succeeded.
        case didCheckOut(
            package: PackageIdentity,
            repository: URL,
            revision: String,
            at: AbsolutePath,
            duration: SendableTimeInterval
        )

        /// The workspace is removing this repository because it is no longer needed.
        case removing(package: PackageIdentity, packageLocation: String?)

        /// Called when the resolver begins to be compute the version for the repository.
        case willComputeVersion(package: PackageIdentity, location: String)
        /// Called when the resolver finished computing the version for the repository.
        case didComputeVersion(package: PackageIdentity, location: String, version: String, duration: SendableTimeInterval)

        /// Called when the Package.resolved file is changed *outside* of libSwiftPM operations.
        ///
        /// This is only fired when activated using Workspace's watchResolvedFile() method.
        case resolvedFileChanged

        /// The workspace has started downloading a binary artifact.
        case willDownloadBinaryArtifact(from: URL)
        /// The workspace has finished downloading a binary artifact.
        case didDownloadBinaryArtifact(from: URL, result: Result<AbsolutePath, Error>, duration: SendableTimeInterval)
        /// The workspace is downloading a binary artifact.
        case downloadingBinaryArtifact(from: URL, bytesDownloaded: Int64, totalBytesToDownload: Int64?)
        /// The workspace finished downloading all binary artifacts.
        case didDownloadAllBinaryArtifacts

        /// The workspace has started updating dependencies
        case willUpdateDependencies
        /// The workspace has finished updating dependencies
        case didUpdateDependencies(duration: SendableTimeInterval)

        /// Called when the resolver is about to be run.
        case willResolveDependencies(reason: WorkspaceResolveReason)
        /// The workspace has finished resolving dependencies
        case didResolveDependencies(duration: SendableTimeInterval)

        /// The workspace has started loading the graph to memory
        case willLoadGraph
        /// The workspace has finished loading the graph to memory
        case didLoadGraph(duration: SendableTimeInterval)
    }
}
