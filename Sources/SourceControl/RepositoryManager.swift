/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Dispatch
import class Foundation.OperationQueue

import Basic
import Utility

/// Delegate to notify clients about actions being performed by RepositoryManager.
public protocol RepositoryManagerDelegate: class {
    /// Called when a repository is about to be fetched.
    func fetching(handle: RepositoryManager.RepositoryHandle, to path: AbsolutePath)
}

/// Manages a collection of bare repositories.
public class RepositoryManager {

    public typealias LookupResult = Result<RepositoryHandle, AnyError>
    public typealias LookupCompletion = (LookupResult) -> ()

    /// Handle to a managed repository.
    public class RepositoryHandle {
        enum Status: String {
            /// The repository has not been requested.
            case uninitialized
            
            /// The repository is being fetched.
            case pending

            /// The repository is available.
            case available

            /// The repository was unable to be fetched.
            case error
        }
        
        /// The manager this repository is owned by.
        private unowned let manager: RepositoryManager

        /// The repository specifier.
        public let repository: RepositorySpecifier

        /// The subpath of the repository within the manager.
        ///
        /// This is intentionally hidden from the clients so that the manager is
        /// allowed to move repositories transparently.
        fileprivate let subpath: RelativePath

        /// The status of the repository.
        fileprivate var status: Status = .uninitialized

        /// The serial queue to perform the operations like updating the state of the handle and fetching the repositories
        /// from its remote. The advantage of having a serial queue in handle is that we don't have to worry about multiple lookups on the same handle as they will be queued automatically.
        fileprivate let serialQueue = DispatchQueue(label: "org.swift.swiftpm.repohandle-serial")

        /// If the repository needs to be fetched, due to being possibly outdated.
        ///
        /// If we have just created this handle, we don't need to fetch the repository handled
        /// by this instance. If we're loading this handle from a saved state, it may be possible that
        /// the copy on disk has become outdated and we should fetch it from remote.
        fileprivate var needsFetch: Bool

        /// Create a handle.
        fileprivate init(manager: RepositoryManager, repository: RepositorySpecifier, subpath: RelativePath) {
            self.manager = manager
            self.repository = repository
            self.subpath = subpath
            self.needsFetch = false
        }

        /// Create a handle from JSON data.
        fileprivate init?(manager: RepositoryManager, json data: JSON) {
            guard case let .dictionary(contents) = data,
                  case let .string(subpath)? = contents["subpath"],
                  case let .string(repositoryURL)? = contents["repositoryURL"],
                  case let .string(statusString)? = contents["status"],
                  let status = Status(rawValue: statusString) else {
                return nil
            }
            self.manager = manager
            self.repository = RepositorySpecifier(url: repositoryURL)
            self.subpath = RelativePath(subpath)
            self.status = status
            self.needsFetch = true
        }
        
        /// Open the given repository.
        public func open() throws -> Repository {
            precondition(status == .available, "open() called in invalid state")
            return try self.manager.open(self)
        }

        /// Clone into a working copy at on the local file system.
        ///
        /// - Parameters:
        ///   - path: The path at which to create the working copy; it is
        ///     expected to be non-existent when called.
        ///   - editable: The clone is expected to be edited by user.
        public func cloneCheckout(to path: AbsolutePath, editable: Bool) throws {
            precondition(status == .available, "cloneCheckout() called in invalid state")
            try self.manager.cloneCheckout(self, to: path, editable: editable)
        }

        // MARK: Persistence

        fileprivate func toJSON() -> JSON {
            return .dictionary([
                    "status": .string(status.rawValue),
                    "repositoryURL": .string(repository.url),
                    "subpath": .string(subpath.asString)
                ])
        }
    }

    /// The path under which repositories are stored.
    public let path: AbsolutePath

    /// The repository provider.
    public let provider: RepositoryProvider

    /// The delegate interface.
    private let delegate: RepositoryManagerDelegate

    /// The map of registered repositories.
    //
    // FIXME: We should use a more sophisticated map here, which tracks the full
    // specifier but then is capable of efficiently determining if two
    // repositories map to the same location.
    private var repositories: [String: RepositoryHandle] = [:]
        
    /// Queue to protect concurrent reads and mutations to repositories registery.
    private let serialQueue = DispatchQueue(label: "org.swift.swiftpm.repomanagerqueue-serial")

    /// Operation queue to do concurrent operations on manager.
    ///
    /// We use operation queue (and not dispatch queue) to limit the amount of concurrent operations.
    private let operationQueue: OperationQueue

    /// The filesystem to operate on.
    private var fileSystem: FileSystem

    /// Create a new empty manager.
    ///
    /// - Parameters:
    ///   - path: The path under which to store repositories. This should be a
    ///           directory in which the content can be completely managed by this
    ///           instance.
    ///   - provider: The repository provider.
    ///   - delegate: The repository manager delegate.
    ///   - fileSystem: The filesystem to operate on.
    public init(path: AbsolutePath, provider: RepositoryProvider, delegate: RepositoryManagerDelegate, fileSystem: FileSystem = localFileSystem) {
        self.path = path
        self.provider = provider
        self.delegate = delegate
        self.fileSystem = fileSystem

        self.operationQueue = OperationQueue()
        self.operationQueue.name = "org.swift.swiftpm.repomanagerqueue-concurrent"
        self.operationQueue.maxConcurrentOperationCount = 10

        // Load the state from disk, if possible.
        do {
            _ = try restoreState()
        } catch {
            // State restoration errors are ignored, for now.
            //
            // FIXME: We need to do something better here.
            print("warning: unable to restore checkouts state: \(error)")
        }
    }

    /// Get a handle to a repository.
    ///
    /// This will initiate a clone of the repository automatically, if necessary.
    public func lookup(repository: RepositorySpecifier, completion: @escaping LookupCompletion) {
        operationQueue.addOperation {
            // First look for the handle.
            let handle = self.getHandle(repository: repository)
            // Dispatch the action we want to take on the serial queue of the handle.
            handle.serialQueue.sync {
                let result: LookupResult
                switch handle.status {
                case .available:
                    result = LookupResult(anyError: {
                        // Fetch and update the repository when it is being looked up.
                        if handle.needsFetch {
                            let repo = try handle.open()
                            try repo.fetch()
                            // Toggle so we don't fetch it again on next lookup.
                            handle.needsFetch = false
                        }
                        return handle
                    })
                case .pending:
                    precondition(false, "This should never have been called")
                    return
                case .uninitialized, .error:
                    // Change the state to pending.
                    handle.status = .pending
                    let repositoryPath = self.path.appending(handle.subpath)
                    // Make sure desination is free.
                    self.fileSystem.removeFileTree(repositoryPath)

                    // Fetch the repo.
                    do {
                        // Inform delegate.
                        DispatchQueue.global().async {
                            self.delegate.fetching(handle: handle, to: repositoryPath)
                        }
                        // Start fetching.
                        try self.provider.fetch(repository: handle.repository, to: repositoryPath)
                        // Update status to available.
                        handle.status = .available
                        result = Result(handle)
                    } catch {
                        handle.status = .error
                        result = Result(error)
                    }
                    // Save the manager state.
                    self.serialQueue.sync { 
                        do {
                            try self.saveState()
                        } catch {
                            // FIXME: Handle failure gracefully, somehow.
                            fatalError("unable to save manager state \(error)")
                            
                        }
                    }
                }
                // Call the completion handler on the global queue otherwise,
                // nested calls to lookup on same handle will block.
                DispatchQueue.global().async {
                    completion(result)
                }
            }
        }
    }

    /// Returns the handle for repository if available, otherwise creates a new one.
    /// Note: This method is thread safe.
    private func getHandle(repository: RepositorySpecifier) -> RepositoryHandle {
        return serialQueue.sync {
            let handle: RepositoryHandle
            if let oldHandle = self.repositories[repository.url] {
                handle = oldHandle
            } else {
                let subpath = RelativePath(repository.fileSystemIdentifier)
                let newHandle = RepositoryHandle(manager: self, repository: repository, subpath: subpath)
                self.repositories[repository.url] = newHandle
                handle = newHandle
            }
            return handle
        }
    }

    /// Synchronous variation of lookup(repository:) method.
    public func lookupSynchronously(repository: RepositorySpecifier) throws -> RepositoryHandle {
        let lookupCondition = Condition()
        var result: Result<RepositoryHandle, AnyError>? = nil
        lookup(repository: repository) { theResult in
            lookupCondition.whileLocked {
                result = theResult
                lookupCondition.signal()
            }
        }
        lookupCondition.whileLocked { 
            while result == nil {
                lookupCondition.wait()
            }
        }
        return try result!.dematerialize()
    }

    /// Open a repository from a handle.
    private func open(_ handle: RepositoryHandle) throws -> Repository {
        return try provider.open(repository: handle.repository, at: path.appending(handle.subpath))
    }

    /// Clone a repository from a handle.
    private func cloneCheckout(_ handle: RepositoryHandle, to destinationPath: AbsolutePath, editable: Bool) throws {
        try provider.cloneCheckout(repository: handle.repository, at: path.appending(handle.subpath), to: destinationPath, editable: editable)
    }

    /// Removes the repository.
    public func remove(repository: RepositorySpecifier) throws {
        try serialQueue.sync {
            // If repository isn't present, we're done.
            guard let handle = repositories[repository.url] else {
                return
            }
            repositories[repository.url] = nil
            let repositoryPath = path.appending(handle.subpath)
            fileSystem.removeFileTree(repositoryPath)
            try self.saveState()
        }
    }

    /// Reset the repository manager.
    ///
    /// Note: This also removes the cloned repositories from the disk.
    public func reset() {
        serialQueue.sync {
            self.repositories = [:]
            self.fileSystem.removeFileTree(path)
        }
    }

    // MARK: Persistence

    private enum PersistenceError: Swift.Error {
        /// The schema does not match the current version.
        case invalidVersion
        
        /// There was a missing or malformed key.
        case unexpectedData
    }
    
    /// The schema of the state file.
    ///
    /// We currently discard any restored state if we detect a schema change.
    private static var schemaVersion = 1

    /// The path at which we persist the manager state.
    var statePath: AbsolutePath {
        return path.appending(component: "checkouts-state.json")
    }
    
    /// Restore the manager state from disk.
    ///
    /// - Throws: A PersistenceError if the state was available, but could not
    /// be restored.
    ///
    /// - Returns: True if the state was restored, or false if the state wasn't
    /// available.
    private func restoreState() throws -> Bool {
        // If the state doesn't exist, don't try to load and fail.
        if !fileSystem.exists(statePath) {
            return false
        }
        
        // Load the state.
        let json = try JSON(bytes: try fileSystem.readFileContents(statePath))

        // Load the state from JSON.
        guard case let .dictionary(contents) = json,
              case let .int(version)? = contents["version"] else {
            throw PersistenceError.unexpectedData
        }
        guard version == RepositoryManager.schemaVersion else {
            throw PersistenceError.invalidVersion
        }
        guard case let .array(repositoriesData)? = contents["repositories"] else {
            throw PersistenceError.unexpectedData
        }

        // Load the repositories.
        var repositories = [String: RepositoryHandle]()
        for repositoryData in repositoriesData {
            guard case let .dictionary(contents) = repositoryData,
                  case let .string(key)? = contents["key"],
                  case let handleData? = contents["handle"],
                  case let handle = RepositoryHandle(manager: self, json: handleData) else {
                throw PersistenceError.unexpectedData
            }
            repositories[key] = handle

            // FIXME: We may need to validate the integrity of this
            // repository. However, we might want to recover from that on
            // the common path too, so it might prove unnecessary...
        }

        self.repositories = repositories

        return true
    }
    
    /// Write the manager state to disk.
    private func saveState() throws {
        var data = [String: JSON]()
        data["version"] = .int(RepositoryManager.schemaVersion)
        // FIXME: Should record information on the provider, in case it changes.
        data["repositories"] = .array(repositories.map{ (key, handle) in
                .dictionary([
                        "key": .string(key),
                        "handle": handle.toJSON() ])
            })

        // FIXME: This should write atomically.
        try fileSystem.writeFileContents(statePath, bytes: JSON.dictionary(data).toBytes())
    }
}

extension RepositoryManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(type(of: self)) subpath:\(subpath.asString)>"
    }
}
