/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

/// Manages a collection of repository checkouts.
public class CheckoutManager {
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
        private unowned let manager: CheckoutManager

        /// The repository specifier.
        fileprivate let repository: RepositorySpecifier

        /// The subpath of the repository within the manager.
        ///
        /// This is intentionally hidden from the clients so that the manager is
        /// allowed to move repositories transparently.
        fileprivate let subpath: RelativePath

        /// The status of the repository.
        fileprivate var status: Status = .uninitialized

        /// Create a handle.
        fileprivate init(manager: CheckoutManager, repository: RepositorySpecifier, subpath: RelativePath) {
            self.manager = manager
            self.repository = repository
            self.subpath = subpath
        }

        /// Create a handle from JSON data.
        fileprivate init?(manager: CheckoutManager, json data: JSON) {
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
        }
        
        /// Check if the repository has been fetched.
        public var isAvailable: Bool {
            switch status {
            case .available:
                return true
            default:
                return false
            }
        }
    
        /// Add a function to be called when the repository is available.
        ///
        /// This function will be called on an unspecified thread when the
        /// repository fetch operation is complete.
        public func addObserver(whenFetched body: (RepositoryHandle) -> ()) {
            // The current manager is not concurrent, so this has a trivial
            // (synchronous) implementation.
            switch status {
            case .uninitialized, .pending:
                fatalError("unexpected state")
            case .available, .error:
                body(self)
            }
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
        public func cloneCheckout(to path: AbsolutePath) throws {
            precondition(status == .available, "cloneCheckout() called in invalid state")
            try self.manager.cloneCheckout(self, to: path)
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

    /// The map of registered repositories.
    //
    // FIXME: We should use a more sophisticated map here, which tracks the full
    // specifier but then is capable of efficiently determining if two
    // repositories map to the same location.
    private var repositories: [String: RepositoryHandle] = [:]
        
    /// Create a new empty manager.
    ///
    /// - path: The path under which to store repositories. This should be a
    ///         directory in which the content can be completely managed by this
    ///         instance.
    public init(path: AbsolutePath, provider: RepositoryProvider) {
        self.path = path
        self.provider = provider

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
    /// This will initiate a clone of the repository automatically, if
    /// necessary, and immediately return. The client can add observers to the
    /// result in order to know when the repository is available.
    public func lookup(repository: RepositorySpecifier) -> RepositoryHandle {
        // Check to see if the repository has been provided.
        if let handle = repositories[repository.url] {
            return handle
        }
        
        // Otherwise, fetch the repository and return a handle.
        let subpath = RelativePath(repository.fileSystemIdentifier)
        let handle = RepositoryHandle(manager: self, repository: repository, subpath: subpath)
        repositories[repository.url] = handle

        // Ensure nothing else exists at the subpath.
        let repositoryPath = path.appending(subpath)
        if localFileSystem.exists(repositoryPath) {
            _ = try? removeFileTree(repositoryPath)
        }
        
        // FIXME: This should run on a background thread.
        do {
            handle.status = .pending
            try provider.fetch(repository: repository, to: repositoryPath)
            handle.status = .available
        } catch {
            // FIXME: Handle failure more sensibly.
            handle.status = .error
        }

        // Save the manager state.
        do {
            try saveState()
        } catch {
            // FIXME: Handle failure gracefully, somehow.
            fatalError("unable to save manager state")
        }
        
        return handle
    }

    /// Open a repository from a handle.
    private func open(_ handle: RepositoryHandle) throws -> Repository {
        return try provider.open(repository: handle.repository, at: path.appending(handle.subpath))
    }

    /// Clone a repository from a handle.
    private func cloneCheckout(_ handle: RepositoryHandle, to destinationPath: AbsolutePath) throws {
        try provider.cloneCheckout(repository: handle.repository, at: path.appending(handle.subpath), to: destinationPath)
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
        if !exists(statePath) {
            return false
        }
        
        // Load the state.
        let json = try JSON(bytes: try localFileSystem.readFileContents(statePath))

        // Load the state from JSON.
        guard case let .dictionary(contents) = json,
              case let .int(version)? = contents["version"] else {
            throw PersistenceError.unexpectedData
        }
        guard version == CheckoutManager.schemaVersion else {
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
        data["version"] = .int(CheckoutManager.schemaVersion)
        // FIXME: Should record information on the provider, in case it changes.
        data["repositories"] = .array(repositories.map{ (key, handle) in
                .dictionary([
                        "key": .string(key),
                        "handle": handle.toJSON() ])
            })

        // FIXME: This should write atomically.
        try localFileSystem.writeFileContents(statePath, bytes: JSON.dictionary(data).toBytes())
    }
}

extension CheckoutManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(type(of: self)) subpath:\(subpath.asString)>"
    }
}
