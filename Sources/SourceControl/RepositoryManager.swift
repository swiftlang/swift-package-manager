//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
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
import PackageModel
import TSCBasic

/// Manages a collection of bare repositories.
public class RepositoryManager: Cancellable {
    public typealias Delegate = RepositoryManagerDelegate

    /// The path under which repositories are stored.
    public let path: Basics.AbsolutePath

    /// The path to the directory where all cached git repositories are stored.
    private let cachePath: Basics.AbsolutePath?

    // used in tests to disable skipping of local packages.
    private let cacheLocalPackages: Bool

    /// The repository provider.
    private let provider: RepositoryProvider

    /// The delegate interface.
    private let delegate: RepositoryManagerDelegateProxy?

    /// The filesystem to operate on.
    private let fileSystem: FileSystem

    // tracks outstanding lookups for de-duping requests
    private var pendingLookups = [RepositorySpecifier: Task<RepositoryManager.RepositoryHandle, Error>]()
    private var pendingLookupsLock = NSLock()

    // Limits how many concurrent operations can be performed at once.
    private let asyncOperationQueue: AsyncOperationQueue

    private var emitNoConnectivityWarning = ThreadSafeBox<Bool>(true)

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
    ///   - maxConcurrentOperations: Max concurrent lookup operations
    ///   - initializationWarningHandler: Initialization warnings handler.
    ///   - delegate: The repository manager delegate.
    public init(
        fileSystem: FileSystem,
        path: Basics.AbsolutePath,
        provider: RepositoryProvider,
        cachePath: Basics.AbsolutePath? =  .none,
        cacheLocalPackages: Bool = false,
        maxConcurrentOperations: Int? = .none,
        initializationWarningHandler: (String) -> Void,
        delegate: Delegate? = .none
    ) {
        self.fileSystem = fileSystem
        self.path = path
        self.cachePath = cachePath
        self.cacheLocalPackages = cacheLocalPackages

        self.provider = provider
        self.delegate = RepositoryManagerDelegateProxy(delegate)

        // this queue and semaphore is used to limit the amount of concurrent git operations taking place
        let maxConcurrentOperations = max(1, maxConcurrentOperations ?? (3 * Concurrency.maxOperations / 4))
        self.asyncOperationQueue = AsyncOperationQueue(concurrentTasks: maxConcurrentOperations)
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
    ///   - updateStrategy: strategy to update the repository.
    ///   - observabilityScope: The observability scope
    ///   - delegateQueue: Dispatch queue for delegate events
    ///   - callbackQueue: Dispatch queue for callbacks
    ///   - completion: The completion block that should be called after lookup finishes.
    @available(*, noasync, message: "Use the async alternative")
    public func lookup(
        package: PackageIdentity,
        repository: RepositorySpecifier,
        updateStrategy: RepositoryUpdateStrategy,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping @Sendable (Result<RepositoryHandle, Error>) -> Void
    ) {
        callbackQueue.asyncResult(completion) {
            // check if the repository is already being looked up
            // if so, wait for it to finish and return the result
            try await self.lookup(
                package: package,
                repository: repository,
                updateStrategy: updateStrategy,
                observabilityScope: observabilityScope
            )
        }
    }

    public func lookup(
        package: PackageIdentity,
        repository repositorySpecifier: RepositorySpecifier,
        updateStrategy: RepositoryUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> RepositoryHandle {
        return try await self.asyncOperationQueue.withOperation {
            let task = await withCheckedContinuation { continuation in
                self.pendingLookupsLock.lock()
                defer { self.pendingLookupsLock.unlock() }

                let lookupTask: Task<RepositoryManager.RepositoryHandle, any Error>
                if let inFlight = self.pendingLookups[repositorySpecifier] {
                    lookupTask = Task {
                        // Let the existing in-flight task finish before queuing up the new one
                        let _ = try await inFlight.value

                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        let result = try await self.performLookup(
                            package: package,
                            repository: repositorySpecifier,
                            updateStrategy: updateStrategy,
                            observabilityScope: observabilityScope
                        )

                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        return result
                    }
                } else {
                    lookupTask = Task {
                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        let result = try await self.performLookup(
                            package: package,
                            repository: repositorySpecifier,
                            updateStrategy: updateStrategy,
                            observabilityScope: observabilityScope
                        )

                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        return result
                    }
                }

                self.pendingLookups[repositorySpecifier] = lookupTask
                continuation.resume(returning: lookupTask)
            }

            do {
                let result = try await task.value
                return result
            } catch {
                throw error
            }
        }
    }

    private func performLookup(
        package: PackageIdentity,
        repository repositorySpecifier: RepositorySpecifier,
        updateStrategy: RepositoryUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> RepositoryHandle {
        let relativePath = try repositorySpecifier.storagePath()
        let repositoryPath = self.path.appending(relativePath)
        let handle = RepositoryHandle(manager: self, repository: repositorySpecifier, subpath: relativePath)
        let delegate = self.delegate

        // check if a repository already exists
        // errors when trying to check if a repository already exists are legitimate
        // and recoverable, and as such can be ignored
        quick: if (try? self.provider.isValidDirectory(repositoryPath)) ?? false {
            let repository = try await handle.open()

            guard ((try? self.provider.isValidDirectory(repositoryPath, for: repositorySpecifier)) ?? false) else {
                observabilityScope.emit(warning: "\(repositoryPath) is not valid git repository for '\(repositorySpecifier.location)', will fetch again.")
                break quick
            }

            // Update the repository if needed
            if self.fetchRequired(repository: repository, updateStrategy: updateStrategy) {
                let start = DispatchTime.now()

                Task {
                    await delegate?.willUpdate(package: package, repository: handle.repository)
                }

                try repository.fetch()
                let duration = start.distance(to: .now())
                Task {
                    await delegate?.didUpdate(package: package, repository: handle.repository, duration: duration)
                }
            }

            return handle
        }

        // inform delegate that we are starting to fetch
        // calculate if cached (for delegate call) outside queue as it may change while queue is processing
        let isCached = self.cachePath.map { self.fileSystem.exists($0.appending(handle.subpath)) } ?? false
        Task {
            let details = FetchDetails(fromCache: isCached, updatedCache: false)
            await delegate?.willFetch(package: package, repository: handle.repository, details: details)
        }

        // perform the fetch
        let start = DispatchTime.now()
        do {
            // make sure destination is free.
            try? self.fileSystem.removeFileTree(repositoryPath)
            // fetch the repo and cache the results
            let result = try await self.fetchAndPopulateCache(
                package: package,
                handle: handle,
                repositoryPath: repositoryPath,
                updateStrategy: updateStrategy,
                observabilityScope: observabilityScope
            )
            // inform delegate fetch is done
            let duration = start.distance(to: .now())
            Task {
                await delegate?.didFetch(package: package, repository: handle.repository, result: .success(result), duration: duration)
            }
            return handle
        } catch {
            // inform delegate fetch is done
            let duration = start.distance(to: .now())
            Task {
                await delegate?.didFetch(package: package, repository: handle.repository, result: .failure(error), duration: duration)
            }
            throw error
        }
    }

    public func cancel(deadline: DispatchTime) throws {
        // ask the provider to cancel
        try self.provider.cancel(deadline: deadline)

        self.pendingLookupsLock.lock()
        defer { self.pendingLookupsLock.unlock() }
        for task in self.pendingLookups.values {
            task.cancel()
        }
        self.pendingLookups = [:]
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
        repositoryPath: Basics.AbsolutePath,
        updateStrategy: RepositoryUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> FetchDetails {
        var cacheUsed = false
        var cacheUpdated = false

        // utility to update progress
        func updateFetchProgress(progress: FetchProgress) -> Void {
            if let total = progress.totalSteps {
                let delegate = self.delegate
                Task {
                    await delegate?.fetching(
                        package: package,
                        repository: handle.repository,
                        objectsFetched: progress.step,
                        totalObjectsToFetch: total
                    )
                }
            }
        }

        // We are expecting handle.repository.url to always be a resolved absolute path.
        let shouldCacheLocalPackages = Environment.current["SWIFTPM_TESTS_PACKAGECACHE"] == "1" || cacheLocalPackages

        if let cachePath, !(handle.repository.isLocal && !shouldCacheLocalPackages) {
            let cachedRepositoryPath = try cachePath.appending(handle.repository.storagePath())
            do {
                try self.initializeCacheIfNeeded(cachePath: cachePath)
                try await self.fileSystem.withLock(on: cachePath, type: .shared) {
                    try await self.fileSystem.withLock(on: cachedRepositoryPath, type: .exclusive) {
                        // Fetch the repository into the cache.
                        if (self.fileSystem.exists(cachedRepositoryPath)) {
                            let repo = try await self.provider.open(repository: handle.repository, at: cachedRepositoryPath)
                            if self.fetchRequired(repository: repo, updateStrategy: updateStrategy) {
                                try repo.fetch(progress: updateFetchProgress(progress:))
                            }
                            cacheUsed = true
                        } else {
                            try await self.provider.fetch(repository: handle.repository, to: cachedRepositoryPath, progressHandler: updateFetchProgress(progress:))
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
                // If we are offline and have a valid cached repository, use the cache anyway.
                if try isOffline(error) && self.provider.isValidDirectory(cachedRepositoryPath, for: handle.repository) {
                    // For the first offline use in the lifetime of this repository manager, emit a warning.
                    if self.emitNoConnectivityWarning.get(default: false) {
                        self.emitNoConnectivityWarning.put(false)
                        observabilityScope.emit(warning: "no connectivity, using previously cached repository state")
                    }
                    observabilityScope.emit(info: "using previously cached repository state for \(package)")

                    cacheUsed = true
                    // Copy the repository from the cache into the repository path.
                    try self.fileSystem.createDirectory(repositoryPath.parentDirectory, recursive: true)
                    try self.provider.copy(from: cachedRepositoryPath, to: repositoryPath)
                } else {
                    cacheUsed = false
                    // Fetch without populating the cache in the case of an error.
                    observabilityScope.emit(
                        warning: "skipping cache due to an error",
                        underlyingError: error
                    )
                    // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
                    try? self.fileSystem.removeFileTree(repositoryPath)
                    try await self.provider.fetch(repository: handle.repository, to: repositoryPath, progressHandler: updateFetchProgress(progress:))
                }
            }
        } else {
            // it is possible that we already created the directory from failed attempts, so clear leftover data if present.
            try? self.fileSystem.removeFileTree(repositoryPath)
            // fetch without populating the cache when no `cachePath` is set.
            try await self.provider.fetch(repository: handle.repository, to: repositoryPath, progressHandler: updateFetchProgress(progress:))
        }
        return FetchDetails(fromCache: cacheUsed, updatedCache: cacheUpdated)
    }

    private func fetchRequired(
        repository: Repository,
        updateStrategy: RepositoryUpdateStrategy
    ) -> Bool {
        switch updateStrategy {
        case .never:
            return false
        case .always:
            return true
        case .ifNeeded(let revision):
            return !repository.exists(revision: revision)
        }
    }

    /// Open a working copy checkout at a path
    public func openWorkingCopy(at path: Basics.AbsolutePath) async throws -> WorkingCheckout {
        try await self.provider.openWorkingCopy(at: path)
    }

    /// Validate a working copy check is aligned with its repository setup
    public func isValidWorkingCopy(_ workingCopy: WorkingCheckout, for repository: RepositorySpecifier) throws -> Bool {
        let relativePath = try repository.storagePath()
        let repositoryPath = self.path.appending(relativePath)
        return workingCopy.isAlternateObjectStoreValid(expected: repositoryPath)
    }

    /// Open a repository from a handle.
    private func open(_ handle: RepositoryHandle) async throws -> Repository {
        try await self.provider.open(
            repository: handle.repository,
            at: self.path.appending(handle.subpath)
        )
    }

    /// Create a working copy of the repository from a handle.
    private func createWorkingCopy(
        _ handle: RepositoryHandle,
        at destinationPath: Basics.AbsolutePath,
        editable: Bool
    ) async throws -> WorkingCheckout {
        try await self.provider.createWorkingCopy(
            repository: handle.repository,
            sourcePath: self.path.appending(handle.subpath),
            at: destinationPath,
            editable: editable)
    }

    /// Removes the repository.
    public func remove(repository: RepositorySpecifier) throws {
        let relativePath = try repository.storagePath()
        let repositoryPath = self.path.appending(relativePath)
        try self.fileSystem.removeFileTree(repositoryPath)
    }

    /// Returns true if the directory is valid git location.
    public func isValidDirectory(_ directory: Basics.AbsolutePath) throws -> Bool {
        try self.provider.isValidDirectory(directory)
    }

    /// Returns true if the directory is valid git location for the specified repository
    public func isValidDirectory(_ directory: Basics.AbsolutePath, for repository: RepositorySpecifier) throws -> Bool {
        try self.provider.isValidDirectory(directory, for: repository)
    }

    /// Reset the repository manager.
    ///
    /// Note: This also removes the cloned repositories from the disk.
    public func reset(observabilityScope: ObservabilityScope) {
        do {
            try self.fileSystem.removeFileTree(self.path)
        } catch {
            observabilityScope.emit(
                error: "Error resetting repository manager at '\(self.path)'",
                underlyingError: error
            )
        }
    }

    /// Sets up the cache directories if they don't already exist.
    private func initializeCacheIfNeeded(cachePath: Basics.AbsolutePath) throws {
        // Create the supplied cache directory.
        if !self.fileSystem.exists(cachePath) {
            try self.fileSystem.createDirectory(cachePath, recursive: true)
        }
    }

    /// Purges the cached repositories from the cache.
    public func purgeCache(observabilityScope: ObservabilityScope) {
        guard let cachePath else {
            return
        }

        guard self.fileSystem.exists(cachePath) else {
            return
        }

        do {
            try self.fileSystem.withLock(on: cachePath, type: .exclusive) {
                let cachedRepositories = try self.fileSystem.getDirectoryContents(cachePath)
                for repoPath in cachedRepositories {
                    let pathToDelete = cachePath.appending(component: repoPath)
                    do {
                        try self.fileSystem.removeFileTree(pathToDelete)
                    } catch {
                        observabilityScope.emit(
                            error: "Error removing cached repository at '\(pathToDelete)'",
                            underlyingError: error
                        )
                    }
                }
            }
        } catch {
            observabilityScope.emit(
                error: "Error purging repository cache at '\(cachePath)'",
                underlyingError: error
            )
        }
    }
}

extension RepositoryManager {
    /// Handle to a managed repository.
    public struct RepositoryHandle: Sendable {
        /// The manager this repository is owned by.
        private unowned let manager: RepositoryManager

        /// The repository specifier.
        public let repository: RepositorySpecifier

        /// The subpath of the repository within the manager.
        ///
        /// This is intentionally hidden from the clients so that the manager is
        /// allowed to move repositories transparently.
        fileprivate let subpath: Basics.RelativePath

        /// Create a handle.
        fileprivate init(manager: RepositoryManager, repository: RepositorySpecifier, subpath: Basics.RelativePath) {
            self.manager = manager
            self.repository = repository
            self.subpath = subpath
        }

        /// Open the given repository.
        public func open() async throws -> Repository {
            return try await self.manager.open(self)
        }

        /// Create a working copy at on the local file system.
        ///
        /// - Parameters:
        ///   - path: The path at which to create the working copy; it is
        ///           expected to be non-existent when called.
        ///
        ///   - editable: The clone is expected to be edited by user.
        public func createWorkingCopy(at path: Basics.AbsolutePath, editable: Bool) async throws -> WorkingCheckout {
            return try await self.manager.createWorkingCopy(self, at: path, editable: editable)
        }
    }
}

extension RepositoryManager {
    /// Additional information about a fetch
    public struct FetchDetails: Equatable, Sendable {
        /// Indicates if the repository was fetched from the cache or from the remote.
        public let fromCache: Bool
        /// Indicates whether the repository was already present in the cache and updated or if a clean fetch was performed.
        public let updatedCache: Bool
    }
}

public enum RepositoryUpdateStrategy: Sendable {
    case never
    case always
    case ifNeeded(revision: Revision)
}

/// Delegate to notify clients about actions being performed by RepositoryManager.
public protocol RepositoryManagerDelegate: Sendable {
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

/// Actor to proxy the delegate methods to the actual delegate, ensuring serialized delegate calls.
fileprivate actor RepositoryManagerDelegateProxy {
    private let delegate: RepositoryManagerDelegate

    init?(_ delegate: RepositoryManagerDelegate?) {
        guard let delegate else {
            return nil
        }
        self.delegate = delegate
    }

    func willFetch(package: PackageIdentity, repository: RepositorySpecifier, details: RepositoryManager.FetchDetails) {
        delegate.willFetch(package: package, repository: repository, details: details)
    }

    func fetching(package: PackageIdentity, repository: RepositorySpecifier, objectsFetched: Int, totalObjectsToFetch: Int) {
        delegate.fetching(package: package, repository: repository, objectsFetched: objectsFetched, totalObjectsToFetch: totalObjectsToFetch)
    }

    func didFetch(package: PackageIdentity, repository: RepositorySpecifier, result: Result<RepositoryManager.FetchDetails, Error>, duration: DispatchTimeInterval) {
        delegate.didFetch(package: package, repository: repository, result: result, duration: duration)
    }

    func willUpdate(package: PackageIdentity, repository: RepositorySpecifier) {
        delegate.willUpdate(package: package, repository: repository)
    }

    func didUpdate(package: PackageIdentity, repository: RepositorySpecifier, duration: DispatchTimeInterval) {
        delegate.didUpdate(package: package, repository: repository, duration: duration)
    }
}


extension RepositoryManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(type(of: self)) subpath:\(subpath)>"
    }
}

extension RepositorySpecifier {
    // relative path where the repository should be stored
    internal func storagePath() throws -> Basics.RelativePath {
        return try RelativePath(validating: self.fileSystemIdentifier)
    }

    /// A unique identifier for this specifier.
    ///
    /// This identifier is suitable for use in a file system path, and
    /// unique for each repository.
    private var fileSystemIdentifier: String {
        // canonicalize across similar locations (mainly for URLs)
        // Use first 8 chars of a stable hash.
        let suffix = self.canonicalLocation.description.sha256Checksum.prefix(8)
        return "\(self.basename)-\(suffix)"
    }
}

extension RepositorySpecifier {
    fileprivate var canonicalLocation: String {
        let canonicalPackageLocation: CanonicalPackageURL = .init(self.location.description)
        return "\(canonicalPackageLocation.description)_\(canonicalPackageLocation.scheme ?? "")"
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

#if canImport(SystemConfiguration)
import SystemConfiguration

private struct Reachability {
    let reachability: SCNetworkReachability

    init?() {
        var emptyAddress = sockaddr()
        emptyAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        emptyAddress.sa_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &emptyAddress, {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }) else {
            return nil
        }
        self.reachability = reachability
    }

    var connectionRequired: Bool {
        var flags = SCNetworkReachabilityFlags()
        let hasFlags = withUnsafeMutablePointer(to: &flags) {
            SCNetworkReachabilityGetFlags(reachability, UnsafeMutablePointer($0))
        }
        guard hasFlags else { return false }
        guard flags.contains(.reachable) else {
            return true
        }
        return flags.contains(.connectionRequired) || flags.contains(.transientConnection)
    }
}

fileprivate func isOffline(_ error: Swift.Error) -> Bool {
    return Reachability()?.connectionRequired == true
}
#else
fileprivate func isOffline(_ error: Swift.Error) -> Bool {
    // TODO: Find a better way to determine reachability on non-Darwin platforms.
    return "\(error)".contains("Could not resolve host")
}
#endif

