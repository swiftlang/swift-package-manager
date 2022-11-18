//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import CoreCommands
import Dispatch
import class Foundation.NSLock
import OrderedCollections
import PackageGraph
import PackageModel
import SPMBuildCore
import Workspace

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.OutputByteStream

class ToolWorkspaceDelegate: WorkspaceDelegate {
    private struct DownloadProgress {
        let bytesDownloaded: Int64
        let totalBytesToDownload: Int64
    }

    private struct FetchProgress {
        let progress: Int64
        let total: Int64
    }

    /// The progress of binary downloads.
    private var binaryDownloadProgress = OrderedCollections.OrderedDictionary<String, DownloadProgress>()
    private let binaryDownloadProgressLock = NSLock()

    /// The progress of package  fetch operations.
    private var fetchProgress = OrderedCollections.OrderedDictionary<PackageIdentity, FetchProgress>()
    private let fetchProgressLock = NSLock()

    private let observabilityScope: ObservabilityScope

    private let outputHandler: (String, Bool) -> Void
    private let progressHandler: (Int64, Int64, String?) -> Void

    init(
        observabilityScope: ObservabilityScope,
        outputHandler: @escaping (String, Bool) -> Void,
        progressHandler: @escaping (Int64, Int64, String?) -> Void
    ) {
        self.observabilityScope = observabilityScope
        self.outputHandler = outputHandler
        self.progressHandler = progressHandler
    }

    func willFetchPackage(package: PackageIdentity, packageLocation: String?, fetchDetails: PackageFetchDetails) {
        self.outputHandler("Fetching \(packageLocation ?? package.description)\(fetchDetails.fromCache ? " from cache" : "")", false)
    }

    func didFetchPackage(package: PackageIdentity, packageLocation: String?, result: Result<PackageFetchDetails, Error>, duration: DispatchTimeInterval) {
        guard case .success = result, !self.observabilityScope.errorsReported else {
            return
        }

        self.fetchProgressLock.withLock {
            let progress = self.fetchProgress.values.reduce(0) { $0 + $1.progress }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.total }

            if progress == total && !self.fetchProgress.isEmpty {
                self.fetchProgress.removeAll()
            } else {
                self.fetchProgress[package] = nil
            }
        }

        self.outputHandler("Fetched \(packageLocation ?? package.description) (\(duration.descriptionInSeconds))", false)
    }

    func fetchingPackage(package: PackageIdentity, packageLocation: String?, progress: Int64, total: Int64?) {
        let (step, total, packages) = self.fetchProgressLock.withLock { () -> (Int64, Int64, String) in
            self.fetchProgress[package] = FetchProgress(
                progress: progress,
                total: total ?? progress
            )

            let progress = self.fetchProgress.values.reduce(0) { $0 + $1.progress }
            let total = self.fetchProgress.values.reduce(0) { $0 + $1.total }
            let packages = self.fetchProgress.keys.map { $0.description }.joined(separator: ", ")
            return (progress, total, packages)
        }
        self.progressHandler(step, total, "Fetching \(packages)")
    }

    func willUpdateRepository(package: PackageIdentity, repository url: String) {
        self.outputHandler("Updating \(url)", false)
    }

    func didUpdateRepository(package: PackageIdentity, repository url: String, duration: DispatchTimeInterval) {
        self.outputHandler("Updated \(url) (\(duration.descriptionInSeconds))", false)
    }

    func dependenciesUpToDate() {
        self.outputHandler("Everything is already up-to-date", false)
    }

    func willCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {
        self.outputHandler("Creating working copy for \(url)", false)
    }

    func didCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {
        self.outputHandler("Working copy of \(url) resolved at \(revision)", false)
    }

    func removing(package: PackageIdentity, packageLocation: String?) {
        self.outputHandler("Removing \(packageLocation ?? package.description)", false)
    }

    func willResolveDependencies(reason: WorkspaceResolveReason) {
        self.outputHandler(Workspace.format(workspaceResolveReason: reason), true)
    }

    func willComputeVersion(package: PackageIdentity, location: String) {
        self.outputHandler("Computing version for \(location)", false)
    }

    func didComputeVersion(package: PackageIdentity, location: String, version: String, duration: DispatchTimeInterval) {
        self.outputHandler("Computed \(location) at \(version) (\(duration.descriptionInSeconds))", false)
    }

    func willDownloadBinaryArtifact(from url: String) {
        self.outputHandler("Downloading binary artifact \(url)", false)
    }

    func didDownloadBinaryArtifact(from url: String, result: Result<AbsolutePath, Error>, duration: DispatchTimeInterval) {
        guard case .success = result, !self.observabilityScope.errorsReported else {
            return
        }

        self.binaryDownloadProgressLock.withLock {
            let progress = self.binaryDownloadProgress.values.reduce(0) { $0 + $1.bytesDownloaded }
            let total = self.binaryDownloadProgress.values.reduce(0) { $0 + $1.totalBytesToDownload }

            if progress == total && !self.binaryDownloadProgress.isEmpty {
                self.binaryDownloadProgress.removeAll()
            } else {
                self.binaryDownloadProgress[url] = nil
            }
        }

        self.outputHandler("Downloaded \(url) (\(duration.descriptionInSeconds))", false)
    }

    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {
        let (step, total, artifacts) = self.binaryDownloadProgressLock.withLock { () -> (Int64, Int64, String) in
            self.binaryDownloadProgress[url] = DownloadProgress(
                bytesDownloaded: bytesDownloaded,
                totalBytesToDownload: totalBytesToDownload ?? bytesDownloaded
            )

            let step = self.binaryDownloadProgress.values.reduce(0, { $0 + $1.bytesDownloaded })
            let total = self.binaryDownloadProgress.values.reduce(0, { $0 + $1.totalBytesToDownload })
            let artifacts = self.binaryDownloadProgress.keys.joined(separator: ", ")
            return (step, total, artifacts)
        }

        self.progressHandler(step, total, "Downloading \(artifacts)")
    }

    // noop

    func willLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind) {}
    func didLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Basics.Diagnostic]) {}
    func willCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {}
    func didCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {}
    func resolvedFileChanged() {}
    func didDownloadAllBinaryArtifacts() {}
}

public extension SwiftCommand {
    var workspaceDelegateProvider: WorkspaceDelegateProvider {
        return {
            ToolWorkspaceDelegate(observabilityScope: $0, outputHandler: $1, progressHandler: $2)
        }
    }

    var workspaceLoaderProvider: WorkspaceLoaderProvider {
        return {
            XcodeWorkspaceLoader(fileSystem: $0, observabilityScope: $1)
        }
    }
}
