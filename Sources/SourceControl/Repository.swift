/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// Specifies a repository address.
public struct RepositorySpecifier: Hashable {
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
        // FIXME: Need to do something better here. In particular, we should use
        // a stable hash function since this interacts with the RepositoryManager
        // persistence.
        let basename = url.components(separatedBy: "/").last!
        return basename + "-" + String(url.hashValue)
    }

    public var hashValue: Int {
        return url.hashValue
    }
}
public func ==(lhs: RepositorySpecifier, rhs: RepositorySpecifier) -> Bool {
    return lhs.url == rhs.url
}

/// A repository provider.
///
/// This protocol defines the lower level interface used to to access
/// repositories. High-level clients should access repositories via a
/// `RepositoryManager`.
public protocol RepositoryProvider {
    /// Fetch the complete repository at the given location to `path`.
    ///
    /// - Throws: If there is an error fetching the repository.
    func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws

    /// Open the given repository.
    ///
    /// - Parameters:
    ///   - repository: The specifier for the repository.
    ///   - path: The location of the repository on disk, at which the
    ///     repository has previously been created via `fetch`.
    /// - Throws: If the repository is unable to be opened.
    func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository

    /// Clone a managed repository into a working copy at on the local file system.
    ///
    /// Once complete, the repository can be opened using `openCheckout`.
    ///
    /// - Parameters:
    ///   - sourcePath: The location of the repository on disk, at which the
    ///     repository has previously been created via `fetch`.
    ///   - destinationPath: The path at which to create the working copy; it is
    ///     expected to be non-existent when called.
    ///   - editable: The checkout is expected to be edited by users.
    func cloneCheckout(repository: RepositorySpecifier, at sourcePath: AbsolutePath, to destinationPath: AbsolutePath, editable: Bool) throws

    /// Open a working repository copy.
    ///
    /// - Parameters:
    ///   - path: The location of the repository on disk, at which the
    ///     repository has previously been created via `cloneCheckout`.
    func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout
}

/// Abstract repository operations.
///
/// This interface provides access to an abstracted representation of a
/// repository which is ultimately owned by a `RepositoryManager`. This interface
/// is designed in such a way as to provide the minimal facilities required by
/// the package manager to gather basic information about a repository, but it
/// does not aim to provide all of the interfaces one might want for working
/// with an editable checkout of a repository on disk.
///
/// The goal of this design is to allow the `RepositoryManager` a large degree of
/// flexibility in the storage and maintenance of its underlying repositories.
///
/// This protocol is designed under the assumption that the repository can only
/// be mutated via the functions provided here; thus, e.g., `tags` is expected
/// to be unchanged through the lifetime of an instance except as otherwise
/// documented. The behavior when this assumption is violated is undefined,
/// although the expectation is that implementations should throw or crash when
/// an inconsistency can be detected.
public protocol Repository {
    /// Get the list of tags in the repository.
    var tags: [String] { get }

    /// Resolve the revision for a specific tag.
    ///
    /// - Precondition: The `tag` should be a member of `tags`.
    /// - Throws: If a error occurs accessing the named tag.
    func resolveRevision(tag: String) throws -> Revision

    /// Fetch and update the repository from its remote.
    ///
    /// - Throws: If an error occurs while performing the fetch operation.
    func fetch() throws

    /// Returns true if the given revision exists.
    func exists(revision: Revision) -> Bool

    /// Open an immutable file system view for a particular revision.
    ///
    /// This view exposes the contents of the repository at the given revision
    /// as a file system rooted inside the repository. The repository must
    /// support opening multiple views concurrently, but the expectation is that
    /// clients should be prepared for this to be inefficient when performing
    /// interleaved accesses across separate views (i.e., the repository may
    /// back the view by an actual file system representation of the
    /// repository).
    ///
    /// It is expected behavior that attempts to mutate the given FileSystem
    /// will fail or crash.
    ///
    /// - Throws: If a error occurs accessing the revision.
    func openFileView(revision: Revision) throws -> FileSystem
}

/// An editable checkout of a repository (i.e. a working copy) on the local file
/// system.
public protocol WorkingCheckout {
    /// Get the list of tags in the repository.
    var tags: [String] { get }

    /// Get the current revision.
    func getCurrentRevision() throws -> Revision

    /// Fetch and update the repository from its remote.
    ///
    /// - Throws: If an error occurs while performing the fetch operation.
    func fetch() throws

    /// Query whether the checkout has any commits which are not pushed to its remote.
    func hasUnpushedCommits() throws -> Bool

    /// This check for any modified state of the repository and returns true
    /// if there are uncommited changes.
    func hasUncommitedChanges() -> Bool

    /// Check out the given tag.
    func checkout(tag: String) throws

    /// Check out the given revision.
    func checkout(revision: Revision) throws

    /// Returns true if the given revision exists.
    func exists(revision: Revision) -> Bool

    /// Create a new branch and checkout HEAD to it.
    ///
    /// Note: It is an error to provide a branch name which already exists.
    func checkout(newBranch: String) throws
}

/// A single repository revision.
public struct Revision: Equatable {
    /// A precise identifier for a single repository revision, in a repository-specified manner.
    ///
    /// This string is intended to be opaque to the client, but understandable
    /// by a user. For example, a Git repository might supply the SHA1 of a
    /// commit, or an SVN repository might supply a string such as 'r123'.
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}
public func ==(lhs: Revision, rhs: Revision) -> Bool {
    return lhs.identifier == rhs.identifier
}
