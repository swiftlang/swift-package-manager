//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import Foundation
import PackageLoading
import PackageModel
import TSCBasic

import struct TSCUtility.Version

public class RegistryDownloadsManager: AsyncCancellable {
    public typealias Delegate = RegistryDownloadsManagerDelegate

    private let fileSystem: FileSystem
    private let path: Basics.AbsolutePath
    private let cachePath: Basics.AbsolutePath?
    private let registryClient: RegistryClient
    private let delegate: Delegate?

    struct PackageLookup: Hashable {
        let package: PackageIdentity
        let version: Version
    }

    private var pendingLookups = [PackageLookup: Task<Basics.AbsolutePath, Error>]()
    private var pendingLookupsLock = NSLock()

    public init(
        fileSystem: FileSystem,
        path: Basics.AbsolutePath,
        cachePath: Basics.AbsolutePath?,
        registryClient: RegistryClient,
        delegate: Delegate?
    ) {
        self.fileSystem = fileSystem
        self.path = path
        self.cachePath = cachePath
        self.registryClient = registryClient
        self.delegate = delegate
    }

    public func lookup(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> Basics.AbsolutePath {
        let packageRelativePath: Basics.RelativePath
        let packagePath: Basics.AbsolutePath

        packageRelativePath = try package.downloadPath(version: version)
        packagePath = self.path.appending(packageRelativePath)

        // TODO: we can do some finger-print checking to improve the validation
        // already exists and valid, we can exit early
        if try self.fileSystem.validPackageDirectory(packagePath) {
            return packagePath
        }

        let lookupId = PackageLookup(package: package, version: version)
        let task = await withCheckedContinuation { continuation in
            self.pendingLookupsLock.lock()
            defer { self.pendingLookupsLock.unlock() }

            // Check if we've already resolved/are in the process of resolving for this package.
            if let inFlight = self.pendingLookups[lookupId] {
                continuation.resume(returning: inFlight)
            } else {
                let lookupTask = Task {
                    // inform delegate that we are starting to fetch
                    // calculate if cached (for delegate call) outside queue as it may change while queue is processing
                    let isCached = self.cachePath.map { self.fileSystem.exists($0.appending(packageRelativePath)) } ?? false
                    delegateQueue.async { [delegate = self.delegate] in
                        let details = FetchDetails(fromCache: isCached, updatedCache: false)
                        delegate?.willFetch(package: package, version: version, fetchDetails: details)
                    }

                    // make sure destination is free.
                    try? self.fileSystem.removeFileTree(packagePath)

                    let start = DispatchTime.now()
                    do {
                        let result = try await self.downloadAndPopulateCache(
                            package: package,
                            version: version,
                            packagePath: packagePath,
                            observabilityScope: observabilityScope,
                            delegateQueue: delegateQueue
                        )
                        // inform delegate that we finished to fetch
                        let duration = start.distance(to: .now())
                        delegateQueue.async { [delegate = self.delegate] in
                            delegate?.didFetch(package: package, version: version, result: .success(result), duration: duration)
                        }
                    } catch {
                        let duration = start.distance(to: .now())
                        delegateQueue.async { [delegate = self.delegate] in
                            delegate?.didFetch(package: package, version: version, result: .failure(error), duration: duration)
                        }
                        throw error
                    }
                    return packagePath
                }

                self.pendingLookups[lookupId] = lookupTask
                continuation.resume(returning: lookupTask)
            }
        }
        return try await task.value
    }

    @available(*, noasync, message: "Use the async alternative")
    public func lookup(
        package: PackageIdentity,
        version: Version,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Basics.AbsolutePath, Error>) -> Void
    ) {
        callbackQueue.asyncResult(completion) {
            try await self.lookup(
                package: package,
                version: version,
                observabilityScope: observabilityScope,
                delegateQueue: delegateQueue
            )
        }
    }

    /// Cancel any outstanding requests
    public func cancel(deadline: DispatchTime) async throws {
        try await self.registryClient.cancel(deadline: deadline)
    }

    private func downloadAndPopulateCache(
        package: PackageIdentity,
        version: Version,
        packagePath: Basics.AbsolutePath,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> FetchDetails {
        if let cachePath {
            do {
                let relativePath = try package.downloadPath(version: version)
                let cachedPackagePath = cachePath.appending(relativePath)

                try self.initializeCacheIfNeeded(cachePath: cachePath)

                return try await self.fileSystem.withLock(on: cachedPackagePath, type: .exclusive) {
                    // download the package into the cache unless already exists
                    if try self.fileSystem.validPackageDirectory(cachedPackagePath) {
                        // extra validation to defend from racy edge cases
                        if self.fileSystem.exists(packagePath) {
                            throw StringError("\(packagePath) already exists unexpectedly")
                        }
                        // copy the package from the cache into the package path.
                        try self.fileSystem.createDirectory(packagePath.parentDirectory, recursive: true)
                        try self.fileSystem.copy(from: cachedPackagePath, to: packagePath)
                        return FetchDetails(fromCache: true, updatedCache: false)
                    } else {
                        do {
                            // it is possible that we already created the directory before from failed attempts, so clear leftover data if present.
                            try? self.fileSystem.removeFileTree(cachedPackagePath)
                            // download the package from the registry
                            let _ = try await self.registryClient.downloadSourceArchive(
                                package: package,
                                version: version,
                                destinationPath: cachedPackagePath,
                                progressHandler: updateDownloadProgress,
                                fileSystem: self.fileSystem,
                                observabilityScope: observabilityScope
                            )

                            // extra validation to defend from racy edge cases
                            if self.fileSystem.exists(packagePath) {
                                throw StringError("\(packagePath) already exists unexpectedly")
                            }
                            // copy the package from the cache into the package path.
                            try self.fileSystem.createDirectory(packagePath.parentDirectory, recursive: true)
                            try self.fileSystem.copy(from: cachedPackagePath, to: packagePath)
                            return FetchDetails(fromCache: true, updatedCache: true)
                        } catch {
                            // Wrap this error to do a straight rethrow instead of handling it as if
                            // the download should be made without populating the cache.
                            throw DownloadError.passthrough(error)
                        }
                    }
                }
            } catch DownloadError.passthrough(let underlyingError) {
                throw underlyingError
            } catch {
                // download without populating the cache in the case of an error.
                observabilityScope.emit(
                    warning: "skipping cache due to an error",
                    underlyingError: error
                )
                // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
                try? self.fileSystem.removeFileTree(packagePath)
                let _ = try await self.registryClient.downloadSourceArchive(
                    package: package,
                    version: version,
                    destinationPath: packagePath,
                    progressHandler: updateDownloadProgress,
                    fileSystem: self.fileSystem,
                    observabilityScope: observabilityScope
                )
                return FetchDetails(fromCache: false, updatedCache: false)
            }
        } else {
            // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
            try? self.fileSystem.removeFileTree(packagePath)

            // download without populating the cache when no `cachePath` is set.
            let _ = try await self.registryClient.downloadSourceArchive(
                package: package,
                version: version,
                destinationPath: packagePath,
                progressHandler: updateDownloadProgress,
                fileSystem: self.fileSystem,
                observabilityScope: observabilityScope
            )
            return FetchDetails(fromCache: false, updatedCache: false)
        }

        // utility to update progress

        @Sendable func updateDownloadProgress(downloaded: Int64, total: Int64?) {
            delegateQueue.async { [delegate = self.delegate] in
                delegate?.fetching(
                    package: package,
                    version: version,
                    bytesDownloaded: downloaded,
                    totalBytesToDownload: total
                )
            }
        }

        enum DownloadError: Error {
            case passthrough(Error)
        }
    }

    public func remove(package: PackageIdentity) throws {
        let relativePath = try package.downloadPath()
        let packagesPath = self.path.appending(relativePath)
        self.pendingLookups.removeValue(forPackage: package)
        try self.fileSystem.removeFileTree(packagesPath)
    }

    public func reset(observabilityScope: ObservabilityScope) {
        do {
            try self.fileSystem.removeFileTree(self.path)
        } catch {
            observabilityScope.emit(
                error: "Error resetting registry downloads at '\(self.path)'",
                underlyingError: error
            )
        }
    }

    public func purgeCache(observabilityScope: ObservabilityScope) {
        guard let cachePath else {
            return
        }

        guard self.fileSystem.exists(cachePath) else {
            return
        }

        do {
            try self.fileSystem.withLock(on: cachePath, type: .exclusive) {
                let cachedPackages = try self.fileSystem.getDirectoryContents(cachePath)
                for packagePath in cachedPackages {
                    let pathToDelete = cachePath.appending(component: packagePath)
                    do {
                        try self.fileSystem.removeFileTree(pathToDelete)
                    } catch {
                        observabilityScope.emit(
                            error: "Error removing cached package at '\(pathToDelete)'",
                            underlyingError: error
                        )
                    }
                }
            }
        } catch {
            observabilityScope.emit(
                error: "Error purging registry downloads cache at '\(cachePath)'",
                underlyingError: error
            )
        }
    }

    private func initializeCacheIfNeeded(cachePath: Basics.AbsolutePath) throws {
        if !self.fileSystem.exists(cachePath) {
            try self.fileSystem.createDirectory(cachePath, recursive: true)
        }
    }
}

/// Delegate to notify clients about actions being performed by RegistryManager.
public protocol RegistryDownloadsManagerDelegate: Sendable {
    /// Called when a package is about to be fetched.
    func willFetch(package: PackageIdentity, version: Version, fetchDetails: RegistryDownloadsManager.FetchDetails)

    /// Called when a package has finished fetching.
    func didFetch(
        package: PackageIdentity,
        version: Version,
        result: Result<RegistryDownloadsManager.FetchDetails, Error>,
        duration: DispatchTimeInterval
    )

    /// Called every time the progress of a repository fetch operation updates.
    func fetching(package: PackageIdentity, version: Version, bytesDownloaded: Int64, totalBytesToDownload: Int64?)
}

extension Dictionary where Key == RegistryDownloadsManager.PackageLookup {
    fileprivate mutating func removeValue(forPackage package: PackageIdentity) {
        self.keys
            .filter { $0.package == package }
            .forEach { self.removeValue(forKey: $0) }
    }
}

extension RegistryDownloadsManager {
    /// Additional information about a fetch
    public struct FetchDetails: Equatable, Sendable {
        /// Indicates if the repository was fetched from the cache or from the remote.
        public let fromCache: Bool
        /// Indicates whether the repository was already present in the cache and updated or if a clean fetch was performed.
        public let updatedCache: Bool
    }
}

extension FileSystem {
    func validPackageDirectory(_ path: Basics.AbsolutePath) throws -> Bool {
        if !self.exists(path) {
            return false
        }
        return try self.getDirectoryContents(path).contains(Manifest.filename)
    }
}

extension PackageIdentity {
    internal func downloadPath() throws -> Basics.RelativePath {
        guard let registryIdentity = self.registry else {
            throw StringError("invalid package identifier \(self), expected registry scope and name")
        }
        return try RelativePath(validating: registryIdentity.scope.description).appending(component: registryIdentity.name.description)
    }

    internal func downloadPath(version: Version) throws -> Basics.RelativePath {
        try self.downloadPath().appending(component: version.description)
    }
}
