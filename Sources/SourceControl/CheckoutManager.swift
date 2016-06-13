/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Basic.ByteString
import enum Basic.JSON
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
        
        /// The subpath of the repository within the manager.
        ///
        /// This is intentionally hidden from the clients so that the manager is
        /// allowed to move repositories transparently.
        fileprivate let subpath: String

        /// The status of the repository.
        fileprivate var status: Status = .uninitialized

        /// Create a handle.
        fileprivate init(manager: CheckoutManager, subpath: String) {
            self.manager = manager
            self.subpath = subpath
        }

        /// Create a handle from JSON data.
        fileprivate init?(manager: CheckoutManager, json data: JSON) {
            guard case let .dictionary(contents) = data,
                  case let .string(subpath)? = contents["subpath"],
                  case let .string(statusString)? = contents["status"],
                  let status = Status(rawValue: statusString) else {
                return nil
            }
            self.manager = manager
            self.subpath = subpath
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

        // MARK: Persistence

        fileprivate func toJSON() -> JSON {
            return .dictionary([
                    "status": .string(status.rawValue),
                    "subpath": .string(subpath)
                ])
        }
    }

    /// The path under which repositories are stored.
    private let path: String

    /// The repository provider.
    private let provider: RepositoryProvider

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
    public init(path: String, provider: RepositoryProvider) {
        self.path = path
        self.provider = provider

        // Load the state from disk, if possible.
        do {
            _ = try restoreState()
        } catch {
            // State restoration errors are ignored, for now.
            //
            // FIXME: It would be nice to log this, in some verbose mode.
            print("unable to restore state: \(error)")
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
        let subpath = repository.fileSystemIdentifier
        let handle = RepositoryHandle(manager: self, subpath: subpath)
        repositories[repository.url] = handle

        // FIXME: This should run on a background thread.
        do {
            handle.status = .pending
            try provider.fetch(repository: repository, to: Path.join(path, subpath))
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

    // MARK: Persistence

    fileprivate enum PersistenceError: ErrorProtocol {
        /// The schema does not match the current version.
        case invalidVersion
        
        /// There was a missing or malformed key.
        case unexpectedData
    }
    
    /// The schema of the state file.
    ///
    /// We currently discard any restored state if we detect a schema change.
    private static var schemaVersion = 0

    /// The path at which we persist the manager state.
    private var statePath: String {
        return Path.join(path, "manager-state.json")
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
        if !statePath.exists {
            return false
        }
        
        // Load the state.
        //
        // FIXME: Build out improved file reading support.
        try fopen(statePath) { handle in
            let data = try handle.enumerate().joined(separator: "\n")
            let json = try JSON(bytes: ByteString(encodingAsUTF8: data))

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
        }

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
        try fopen(statePath, mode: .write) { handle in
            try fputs(JSON.dictionary(data).toString(), handle)
        }
    }
}

extension CheckoutManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(self.dynamicType) subpath:\(subpath.debugDescription)>"
    }
}
