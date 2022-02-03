/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Dispatch
import Foundation
import TSCBasic
import PackageModel

/// Manages a collection of bare repositories.
public class RepositoryManager {
    public typealias Delegate = RepositoryManagerDelegate

    /// The path under which repositories are stored.
    public let path: AbsolutePath

    /// The path to the directory where all cached git repositories are stored.
    private let cachePath: AbsolutePath?

    // used in tests to disable skipping of local packages.
    private let cacheLocalPackages: Bool

    /// The repository provider.
    private let provider: RepositoryProvider

    /// The delegate interface.
    private let delegate: Delegate?

    /// DispatchSemaphore to restrict concurrent operations on manager.
    private let lookupSemaphore: DispatchSemaphore

    /// The filesystem to operate on.
    private let fileSystem: FileSystem

    private var pendingLookups = [RepositorySpecifier: DispatchGroup]()
    private var pendingLookupsLock = NSLock()

    /// Create a new empty manager.
    ///
    /// - Parameters:
    ///   - fileSystem: The filesystem to operate on.
    ///   - path: The path under which to store repositories. This should be a
    ///           directory in which the content can be completely managed by this
    ///           instance.
    ///   - provider: The repository provider.
    ///   - cachePath: The repository cache location.
    ///   - cacheLocalPackages: Should cache local packages as well. For testing purposes.
    ///   - initializationWarningHandler: Initialization warnings handler.
    ///   - delegate: The repository manager delegate.
    public init(
        fileSystem: FileSystem,
        path: AbsolutePath,
        provider: RepositoryProvider,
        cachePath: AbsolutePath? =  .none,
        cacheLocalPackages: Bool = false,
        initializationWarningHandler: (String) -> Void,
        delegate: Delegate? = .none
    ) {
        self.fileSystem = fileSystem
        self.path = path
        self.cachePath = cachePath
        self.cacheLocalPackages = cacheLocalPackages

        self.provider = provider
        self.delegate = delegate

        self.lookupSemaphore = DispatchSemaphore(value: Swift.min(3, Concurrency.maxOperations))
    }

    /// Get a handle to a repository.
    ///
    /// This will initiate a clone of the repository automatically, if necessary.
    ///
    /// Note: Recursive lookups are not supported i.e. calling lookup inside
    /// completion block of another lookup will block.
    ///
    /// - Parameters:
    ///   - package: The package identity of the repository to fetch,
    ///   - repository: The repository to look up.
    ///   - skipUpdate: If a repository is available, skip updating it.
    ///   - observabilityScope: The observability scope
    ///   - delegateQueue: Dispatch queue for delegate events
    ///   - callbackQueue: Dispatch queue for callbacks
    ///   - completion: The completion block that should be called after lookup finishes.
    public func lookup(
        package: PackageIdentity,
        repository: RepositorySpecifier,
        skipUpdate: Bool,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<RepositoryHandle, Error>) -> Void
    ) {
        // wrap the callback in the requested queue
        let originalCompletion = completion
        let completion: (Result<RepositoryHandle, Error>) -> Void = { result in
            self.lookupSemaphore.signal()
            callbackQueue.async { originalCompletion(result) }
        }

        self.lookupSemaphore.wait()
        let relativePath = repository.storagePath()
        let repositoryPath = self.path.appending(relativePath)
        let handle = RepositoryManager.RepositoryHandle(manager: self, repository: repository, subpath: relativePath)

        // check if there is a pending lookup
        self.pendingLookupsLock.lock()
        if let pendingLookup = self.pendingLookups[repository] {
            self.pendingLookupsLock.unlock()
            // chain onto the pending lookup
            return pendingLookup.notify(queue: callbackQueue) {
                // at this point the previous lookup should be complete and we can re-lookup
                self.lookup(
                    package: package,
                    repository: repository,
                    skipUpdate: skipUpdate,
                    observabilityScope: observabilityScope,
                    delegateQueue: delegateQueue,
                    callbackQueue: callbackQueue,
                    completion: originalCompletion
                )
            }
        }

        // record the pending lookup
        assert(self.pendingLookups[repository] == nil)
        let group = DispatchGroup()
        group.enter()
        self.pendingLookups[repository] = group
        self.pendingLookupsLock.unlock()

        // check if a repository already exists
        // errors when trying to check if a repository already exists are legitimate
        // and recoverable, and as such can be ignored
        if (try? self.provider.repositoryExists(at: repositoryPath)) ?? false {
            let result = Result<RepositoryHandle, Error>(catching: {
                // skip update if not needed
                if skipUpdate {
                    return handle
                }
                // Update the repository when it is being looked up.
                let start = DispatchTime.now()
                delegateQueue.async {
                    self.delegate?.willUpdate(package: package, repository: handle.repository)
                }
                let repository = try handle.open()
                try repository.fetch()
                let duration = start.distance(to: .now())
                delegateQueue.async {
                    self.delegate?.didUpdate(package: package, repository: handle.repository, duration: duration)
                }
                return handle
            })

            // remove the pending lookup
            self.pendingLookupsLock.lock()
            self.pendingLookups[repository]?.leave()
            self.pendingLookups[repository] = nil
            self.pendingLookupsLock.unlock()
            // and done
            return completion(result)
        }

        // perform the fetch
        // inform delegate that we are starting to fetch
        // calculate if cached (for delegate call) outside queue as it may change while queue is processing
        let isCached = self.cachePath.map{ self.fileSystem.exists($0.appending(handle.subpath)) } ?? false
        delegateQueue.async {
            let details = FetchDetails(fromCache: isCached, updatedCache: false)
            self.delegate?.willFetch(package: package, repository: handle.repository, details: details)
        }

        let start = DispatchTime.now()
        let lookupResult: Result<RepositoryHandle, Error>
        let delegateResult: Result<FetchDetails, Error>

        do {
            // make sure destination is free.
            try? self.fileSystem.removeFileTree(repositoryPath)
            // Fetch the repo.
            let details = try self.fetchAndPopulateCache(
                package: package,
                handle: handle,
                repositoryPath: repositoryPath,
                observabilityScope: observabilityScope,
                delegateQueue: delegateQueue
            )
            lookupResult = .success(handle)
            delegateResult = .success(details)
        } catch {
            lookupResult = .failure(error)
            delegateResult = .failure(error)
        }

        // Inform delegate.
        let duration = start.distance(to: .now())
        delegateQueue.async {
            self.delegate?.didFetch(package: package, repository: handle.repository, result: delegateResult, duration: duration)
        }

        // remove the pending lookup
        self.pendingLookupsLock.lock()
        self.pendingLookups[repository]?.leave()
        self.pendingLookups[repository] = nil
        self.pendingLookupsLock.unlock()
        // and done
        completion(lookupResult)
    }

    /// Fetches the repository into the cache. If no `cachePath` is set or an error occurred fall back to fetching the repository without populating the cache.
    /// - Parameters:
    ///   - package: The package identity of the repository to fetch.
    ///   - handle: The specifier of the repository to fetch.
    ///   - repositoryPath: The path where the repository should be fetched to.
    ///   - observabilityScope: The observability scope
    ///   - delegateQueue: Dispatch queue for delegate events
    @discardableResult
    private func fetchAndPopulateCache(
        package: PackageIdentity,
        handle: RepositoryHandle,
        repositoryPath: AbsolutePath,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) throws -> FetchDetails {
        var cacheUsed = false
        var cacheUpdated = false

        // utility to update progress

        func updateFetchProgress(progress: FetchProgress) -> Void {
            if let total = progress.totalSteps {
                delegateQueue.async {
                    self.delegate?.fetching(
                        package: package,
                        repository: handle.repository,
                        objectsFetched: progress.step,
                        totalObjectsToFetch: total
                    )
                }
            }
        }
        
        // We are expecting handle.repository.url to always be a resolved absolute path.
        let shouldCacheLocalPackages = ProcessEnv.vars["SWIFTPM_TESTS_PACKAGECACHE"] == "1" || cacheLocalPackages

        if let cachePath = self.cachePath, !(handle.repository.isLocal && !shouldCacheLocalPackages) {
            let cachedRepositoryPath = cachePath.appending(handle.repository.storagePath())
            do {
                try self.initializeCacheIfNeeded(cachePath: cachePath)
                try self.fileSystem.withLock(on: cachePath, type: .shared) {
                    try self.fileSystem.withLock(on: cachedRepositoryPath, type: .exclusive) {
                        // Fetch the repository into the cache.
                        if (self.fileSystem.exists(cachedRepositoryPath)) {
                            let repo = try self.provider.open(repository: handle.repository, at: cachedRepositoryPath)
                            try repo.fetch(progress: updateFetchProgress(progress:))
                            cacheUsed = true
                        } else {
                            try self.provider.fetch(repository: handle.repository, to: cachedRepositoryPath, progressHandler: updateFetchProgress(progress:))
                        }
                        cacheUpdated = true
                        // extra validation to defend from racy edge cases
                        if self.fileSystem.exists(repositoryPath) {
                            throw StringError("\(repositoryPath) already exists unexpectedly")
                        }
                        // Copy the repository from the cache into the repository path.
                        try self.fileSystem.createDirectory(repositoryPath.parentDirectory, recursive: true)
                        try self.provider.copy(from: cachedRepositoryPath, to: repositoryPath)
                    }
                }
            } catch {
                cacheUsed = false
                // Fetch without populating the cache in the case of an error.
                observabilityScope.emit(warning: "skipping cache due to an error: \(error)")
                // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
                try? self.fileSystem.removeFileTree(repositoryPath)
                try self.provider.fetch(repository: handle.repository, to: repositoryPath, progressHandler: updateFetchProgress(progress:))
            }
        } else {
            // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
            try? self.fileSystem.removeFileTree(repositoryPath)
            // fetch without populating the cache when no `cachePath` is set.
            try self.provider.fetch(repository: handle.repository, to: repositoryPath, progressHandler: updateFetchProgress(progress:))
        }
        return FetchDetails(fromCache: cacheUsed, updatedCache: cacheUpdated)
    }

    public func openWorkingCopy(at path: AbsolutePath) throws -> WorkingCheckout {
        try self.provider.openWorkingCopy(at: path)
    }

    /// Open a repository from a handle.
    private func open(_ handle: RepositoryHandle) throws -> Repository {
        try self.provider.open(
            repository: handle.repository,
            at: self.path.appending(handle.subpath)
        )
    }

    /// Create a working copy of the repository from a handle.
    private func createWorkingCopy(
        _ handle: RepositoryHandle,
        at destinationPath: AbsolutePath,
        editable: Bool
    ) throws -> WorkingCheckout {
        try self.provider.createWorkingCopy(
            repository: handle.repository,
            sourcePath: self.path.appending(handle.subpath),
            at: destinationPath,
            editable: editable)
    }

    /// Removes the repository.
    public func remove(repository: RepositorySpecifier) throws {
        let relativePath = repository.storagePath()
        let repositoryPath = self.path.appending(relativePath)
        try self.fileSystem.removeFileTree(repositoryPath)
    }

    /// Returns true if the directory is valid git location.
    public func isValidDirectory(_ directory: AbsolutePath) -> Bool {
        self.provider.isValidDirectory(directory)
    }

    /// Returns true if the git reference name is well formed.
    public func isValidRefFormat(_ ref: String) -> Bool {
        self.provider.isValidRefFormat(ref)
    }

    /// Reset the repository manager.
    ///
    /// Note: This also removes the cloned repositories from the disk.
    public func reset() throws {
        try self.fileSystem.removeFileTree(self.path)
    }

    /// Sets up the cache directories if they don't already exist.
    public func initializeCacheIfNeeded(cachePath: AbsolutePath) throws {
        // Create the supplied cache directory.
        if !self.fileSystem.exists(cachePath) {
            try self.fileSystem.createDirectory(cachePath, recursive: true)
        }
    }

    /// Purges the cached repositories from the cache.
    public func purgeCache() throws {
        guard let cachePath = self.cachePath else { return }
        try self.fileSystem.withLock(on: cachePath, type: .exclusive) {
            let cachedRepositories = try self.fileSystem.getDirectoryContents(cachePath)
            for repoPath in cachedRepositories {
                try self.fileSystem.removeFileTree(cachePath.appending(component: repoPath))
            }
        }
    }
}

extension RepositoryManager {
    /// Handle to a managed repository.
    public struct RepositoryHandle {
        /// The manager this repository is owned by.
        private unowned let manager: RepositoryManager

        /// The repository specifier.
        public let repository: RepositorySpecifier

        /// The subpath of the repository within the manager.
        ///
        /// This is intentionally hidden from the clients so that the manager is
        /// allowed to move repositories transparently.
        fileprivate let subpath: RelativePath

        /// Create a handle.
        fileprivate init(manager: RepositoryManager, repository: RepositorySpecifier, subpath: RelativePath) {
            self.manager = manager
            self.repository = repository
            self.subpath = subpath
        }

        /// Open the given repository.
        public func open() throws -> Repository {
            return try self.manager.open(self)
        }

        /// Create a working copy at on the local file system.
        ///
        /// - Parameters:
        ///   - path: The path at which to create the working copy; it is
        ///           expected to be non-existent when called.
        ///
        ///   - editable: The clone is expected to be edited by user.
        public func createWorkingCopy(at path: AbsolutePath, editable: Bool) throws -> WorkingCheckout {
            return try self.manager.createWorkingCopy(self, at: path, editable: editable)
        }
    }
}

extension RepositoryManager {
    /// Additional information about a fetch
    public struct FetchDetails: Equatable {
        /// Indicates if the repository was fetched from the cache or from the remote.
        public let fromCache: Bool
        /// Indicates wether the wether the repository was already present in the cache and updated or if a clean fetch was performed.
        public let updatedCache: Bool
    }
}

/// Delegate to notify clients about actions being performed by RepositoryManager.
public protocol RepositoryManagerDelegate {
    /// Called when a repository is about to be fetched.
    func willFetch(package: PackageIdentity, repository: RepositorySpecifier, details: RepositoryManager.FetchDetails)

    /// Called every time the progress of a repository fetch operation updates.
    func fetching(package: PackageIdentity, repository: RepositorySpecifier, objectsFetched: Int, totalObjectsToFetch: Int)

    /// Called when a repository has finished fetching.
    func didFetch(package: PackageIdentity, repository: RepositorySpecifier, result: Result<RepositoryManager.FetchDetails, Error>, duration: DispatchTimeInterval)

    /// Called when a repository has started updating from its remote.
    func willUpdate(package: PackageIdentity, repository: RepositorySpecifier)

    /// Called when a repository has finished updating from its remote.
    func didUpdate(package: PackageIdentity, repository: RepositorySpecifier, duration: DispatchTimeInterval)
}


extension RepositoryManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(type(of: self)) subpath:\(subpath)>"
    }
}

extension RepositorySpecifier {
    // relative path where the repository should be stored
    internal func storagePath() -> RelativePath {
        return RelativePath(self.fileSystemIdentifier)
    }

    /// A unique identifier for this specifier.
    ///
    /// This identifier is suitable for use in a file system path, and
    /// unique for each repository.
    private var fileSystemIdentifier: String {
        // Use first 8 chars of a stable hash.
        let suffix = self.location.description .sha256Checksum.prefix(8)
        return "\(self.basename)-\(suffix)"
    }
}

extension RepositorySpecifier {
    fileprivate var isLocal: Bool {
        switch self.location {
        case .path:
            return true
        case .url:
            return false
        }
    }
}

