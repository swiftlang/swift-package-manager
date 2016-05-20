/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

/// Specifies a repository address.
public struct RepositorySpecifier {
    /// The URL of the repository.
    public let url: String

    /// Create a specifier.
    public init(url: String) {
        self.url = url
    }
    
    /// A unique identifier for this specifier.
    ///
    /// This identifier is suitable for use in a file system path, and
    /// unique for each repository.
    public var fileSystemIdentifier: String {
        // FIXME: Need to do something better here.
        return url.basename + "-" + String(url.hashValue)
    }
}

/// A repository provider.
public protocol RepositoryProvider {
    /// Fetch the complete repository at the given location to `path`.
    func fetch(repository: RepositorySpecifier, to path: String) throws
}

/// Manages a collection of repository checkouts.
public class CheckoutManager {
    /// Handle to a managed repository.
    public class RepositoryHandle {
        enum Status {
            /// The repository has not be requested.
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
        private let subpath: String

        /// The status of the repository.
        private var status: Status = .uninitialized

        private init(manager: CheckoutManager, subpath: String) {
            self.manager = manager
            self.subpath = subpath
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
            fatalError("FIXME: Not implemented")
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
    /// directory in which the content can be completely managed by this
    /// instance.
    public init(path: String, provider: RepositoryProvider) {
        self.path = path
        self.provider = provider
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

        return handle
    }
}

extension CheckoutManager.RepositoryHandle: CustomStringConvertible {
    public var description: String {
        return "<\(self.dynamicType) subpath:\(subpath.debugDescription)>"
    }
}
