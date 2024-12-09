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
import struct Foundation.URL
import OrderedCollections
import PackageGraph
import PackageModel
import SPMBuildCore
import Workspace

import protocol TSCBasic.OutputByteStream
import struct TSCUtility.Version

final class CommandWorkspaceDelegate: WorkspaceDelegate {
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
    private let inputHandler: (String, (String?) -> Void) -> Void

    init(
        observabilityScope: ObservabilityScope,
        outputHandler: @escaping (String, Bool) -> Void,
        progressHandler: @escaping (Int64, Int64, String?) -> Void,
        inputHandler: @escaping (String, (String?) -> Void) -> Void
    ) {
        self.observabilityScope = observabilityScope
        self.outputHandler = outputHandler
        self.progressHandler = progressHandler
        self.inputHandler = inputHandler
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

        self.outputHandler("Fetched \(packageLocation ?? package.description) from cache (\(duration.descriptionInSeconds))", false)
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

    func didCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath, duration: DispatchTimeInterval) {
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

    func willDownloadBinaryArtifact(from url: String, fromCache: Bool) {
        if fromCache {
            self.outputHandler("Fetching binary artifact \(url) from cache", false)
        } else {
            self.outputHandler("Downloading binary artifact \(url)", false)
        }
    }

    func didDownloadBinaryArtifact(from url: String, result: Result<(path: AbsolutePath, fromCache: Bool), Error>, duration: DispatchTimeInterval) {
        guard case .success(let fetchDetails) = result, !self.observabilityScope.errorsReported else {
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

        if fetchDetails.fromCache {
            self.outputHandler("Fetched \(url) from cache (\(duration.descriptionInSeconds))", false)
        } else {
            self.outputHandler("Downloaded \(url) (\(duration.descriptionInSeconds))", false)
        }
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

    /// The workspace has started downloading a binary artifact.
    func willDownloadPrebuilt(from url: String, fromCache: Bool) {
        if fromCache {
            self.outputHandler("Fetching package prebuilt \(url) from cache", false)
        } else {
            self.outputHandler("Downloading package prebuilt \(url)", false)
        }
    }

    /// The workspace has finished downloading a binary artifact.
    func didDownloadPrebuilt(
        from url: String,
        result: Result<(path: AbsolutePath, fromCache: Bool), Error>,
        duration: DispatchTimeInterval
    ) {
        guard case .success(let fetchDetails) = result, !self.observabilityScope.errorsReported else {
            return
        }

        if fetchDetails.fromCache {
            self.outputHandler("Fetched \(url) from cache (\(duration.descriptionInSeconds))", false)
        } else {
            self.outputHandler("Downloaded \(url) (\(duration.descriptionInSeconds))", false)
        }
    }

    /// The workspace is downloading a binary artifact.
    func downloadingPrebuilt(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {

    }

    /// The workspace finished downloading all binary artifacts.
    func didDownloadAllPrebuilts() {

    }

    // registry signature handlers

    func onUnsignedRegistryPackage(registryURL: URL, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        self.inputHandler("\(package) \(version) from \(registryURL) is unsigned. okay to proceed? (yes/no) ") { response in
            switch response?.lowercased() {
            case "yes":
                completion(true) // continue
            case "no":
                completion(false) // stop resolution
            default:
                self.outputHandler("invalid response: '\(response ?? "")'", false)
                completion(false)
            }
        }
    }

    func onUntrustedRegistryPackage(registryURL: URL, package: PackageModel.PackageIdentity, version: TSCUtility.Version, completion: (Bool) -> Void) {
        self.inputHandler("\(package) \(version) from \(registryURL) is signed with an untrusted certificate. okay to proceed? (yes/no) ") { response in
            switch response?.lowercased() {
            case "yes":
                completion(true) // continue
            case "no":
                completion(false) // stop resolution
            default:
                self.outputHandler("invalid response: '\(response ?? "")'", false)
                completion(false)
            }
        }
    }

    public func willUpdateDependencies() {
        self.observabilityScope.emit(debug: "Updating dependencies")
        os_signpost(.begin, name: SignpostName.updatingDependencies)
    }

    public func didUpdateDependencies(duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Dependencies updated in (\(duration.descriptionInSeconds))")
        os_signpost(.end, name: SignpostName.updatingDependencies)
    }

    public func willResolveDependencies() {
        self.observabilityScope.emit(debug: "Resolving dependencies")
        os_signpost(.begin, name: SignpostName.resolvingDependencies)
    }

    public func didResolveDependencies(duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Dependencies resolved in (\(duration.descriptionInSeconds))")
        os_signpost(.end, name: SignpostName.resolvingDependencies)
    }

    func willLoadGraph() {
        self.observabilityScope.emit(debug: "Loading and validating graph")
        os_signpost(.begin, name: SignpostName.loadingGraph)
    }

    func didLoadGraph(duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Graph loaded in (\(duration.descriptionInSeconds))")
        os_signpost(.end, name: SignpostName.loadingGraph)
    }

    func didCompileManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Compiled manifest for '\(packageIdentity)' (from '\(packageLocation)') in \(duration.descriptionInSeconds)")
    }

    func didEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String, duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Evaluated manifest for '\(packageIdentity)' (from '\(packageLocation)') in \(duration.descriptionInSeconds)")
    }

    func didLoadManifest(packageIdentity: PackageIdentity, packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Basics.Diagnostic], duration: DispatchTimeInterval) {
        self.observabilityScope.emit(debug: "Loaded manifest for '\(packageIdentity)' (from '\(url)') in \(duration.descriptionInSeconds)")
    }

    // noop
    func willCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {}
    func didCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath, duration: DispatchTimeInterval) {}
    func resolvedFileChanged() {}
    func didDownloadAllBinaryArtifacts() {}
    func willCompileManifest(packageIdentity: PackageIdentity, packageLocation: String) {}
    func willEvaluateManifest(packageIdentity: PackageIdentity, packageLocation: String) {}
    func willLoadManifest(packageIdentity: PackageIdentity, packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind) {}
}

public extension _SwiftCommand {
    var workspaceDelegateProvider: WorkspaceDelegateProvider {
        return {
            CommandWorkspaceDelegate(
                observabilityScope: $0,
                outputHandler: $1,
                progressHandler: $2,
                inputHandler: $3
            )
        }
    }

    var workspaceLoaderProvider: WorkspaceLoaderProvider {
        return {
            XcodeWorkspaceLoader(fileSystem: $0, observabilityScope: $1)
        }
    }
}
