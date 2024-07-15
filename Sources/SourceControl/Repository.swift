//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

/// Specifies a repository address.
public struct RepositorySpecifier: Hashable, Sendable {
    public let location: Location

    public init(location: Location) {
        self.location = location
    }

    /// Create a specifier based on a path.
    public init(path: AbsolutePath) {
        self.init(location: .path(path))
    }

    /// Create a specifier on a URL.
    public init(url: SourceControlURL) {
        self.init(location: .url(url))
    }

    /// The location of the repository as string.
    public var url: String {
        switch self.location {
        case .path(let path): return path.pathString
        case .url(let url): return url.absoluteString
        }
    }

    /// Returns the cleaned basename for the specifier.
    public var basename: String {
        // FIXME: this might be wrong
        //var basename = self.url.pathComponents.dropFirst(1).last(where: { !$0.isEmpty }) ?? ""
        var basename = (self.url as NSString).lastPathComponent
        if basename.hasSuffix(".git") {
            basename = String(basename.dropLast(4))
        }
        if basename == "/" {
            return ""
        }
        return basename
    }

    public enum Location: Hashable, CustomStringConvertible, Sendable {
        case path(AbsolutePath)
        case url(SourceControlURL)

        public var description: String {
            switch self {
            case .path(let path):
                return path.pathString
            case .url(let url):
                return url.absoluteString
            }
        }
    }
}

extension RepositorySpecifier: CustomStringConvertible {
    public var description: String {
        return self.location.description
    }
}

/// A repository provider.
///
/// This protocol defines the lower level interface used to to access
/// repositories. High-level clients should access repositories via a
/// `RepositoryManager`.
public protocol RepositoryProvider: Cancellable {
    /// Fetch the complete repository at the given location to `path`.
    ///
    /// - Parameters:
    ///   - repository: The specifier of the repository to fetch.
    ///   - path: The destination path for the fetch.
    ///   - progress: Reports the progress of the current fetch operation.
    /// - Throws: If there is any error fetching the repository.
    func fetch(repository: RepositorySpecifier, to path: AbsolutePath, progressHandler: FetchProgress.Handler?) throws

    /// Open the given repository.
    ///
    /// - Parameters:
    ///   - repository: The specifier of the original repository from which the
    ///     local clone repository was created.
    ///   - path: The location of the repository on disk, at which the
    ///     repository has previously been created via `fetch`.
    ///
    /// - Throws: If the repository is unable to be opened.
    func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository

    /// Create a working copy from a managed repository.
    ///
    /// Once complete, the repository can be opened using `openWorkingCopy`. Note
    /// that there is no requirement that the files have been materialized into
    /// the file system at the completion of this call, since it will always be
    /// followed by checking out the cloned working copy at a particular ref.
    ///
    /// - Parameters:
    ///   - repository: The specifier of the original repository from which the
    ///     local clone repository was created.
    ///   - sourcePath: The location of the repository on disk, at which the
    ///     repository has previously been created via `fetch`.
    ///   - destinationPath: The path at which to create the working copy; it is
    ///     expected to be non-existent when called.
    ///   - editable: The checkout is expected to be edited by users.
    ///
    /// - Throws: If there is any error cloning the repository.
    func createWorkingCopy(
        repository: RepositorySpecifier,
        sourcePath: AbsolutePath,
        at destinationPath: AbsolutePath,
        editable: Bool) throws -> WorkingCheckout

    /// Returns true if a working repository exists at `path`
    func workingCopyExists(at path: AbsolutePath) throws -> Bool

    /// Open a working repository copy.
    ///
    /// - Parameters:
    ///   - path: The location of the repository on disk, at which the repository
    ///     has previously been created via `copyToWorkingDirectory`.
    func openWorkingCopy(at path: AbsolutePath) throws -> WorkingCheckout

    /// Copies the repository at path `from` to path `to`.
    /// - Parameters:
    ///   - sourcePath: the source path.
    ///   - destinationPath: the destination  path.
    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws

    /// Returns true if the directory is valid git location.
    func isValidDirectory(_ directory: AbsolutePath) throws -> Bool

    /// Returns true if the directory is valid git location for the specified repository
    func isValidDirectory(_ directory: AbsolutePath, for repository: RepositorySpecifier) throws -> Bool
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
    func getTags() throws -> [String]

    /// Resolve the revision for a specific tag.
    ///
    /// - Precondition: The `tag` should be a member of `tags`.
    /// - Throws: If a error occurs accessing the named tag.
    func resolveRevision(tag: String) throws -> Revision

    /// Resolve the revision for an identifier.
    ///
    /// The identifier can be a branch name or a revision identifier.
    ///
    /// - Throws: If the identifier can not be resolved.
    func resolveRevision(identifier: String) throws -> Revision

    /// Fetch and update the repository from its remote.
    ///
    /// - Throws: If an error occurs while performing the fetch operation.
    func fetch() throws

    /// Fetch and update the repository from its remote.
    ///
    /// - Throws: If an error occurs while performing the fetch operation.
    func fetch(progress: FetchProgress.Handler?) throws

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
    /// - Throws: If an error occurs accessing the revision.
    func openFileView(revision: Revision) throws -> FileSystem

    /// Open an immutable file system view for a particular tag.
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
    /// - Throws: If an error occurs accessing the revision.
    func openFileView(tag: String) throws -> FileSystem
}

extension Repository {
    public func fetch(progress: FetchProgress.Handler?) throws {
        try fetch()
    }
}

/// An editable checkout of a repository (i.e. a working copy) on the local file
/// system.
public protocol WorkingCheckout {
    /// Get the list of tags in the repository.
    func getTags() throws -> [String]

    /// Get the current revision.
    func getCurrentRevision() throws -> Revision

    /// Fetch and update the repository from its remote.
    ///
    /// - Throws: If an error occurs while performing the fetch operation.
    func fetch() throws

    /// Query whether the checkout has any commits which are not pushed to its remote.
    func hasUnpushedCommits() throws -> Bool

    /// This check for any modified state of the repository and returns true
    /// if there are uncommitted changes.
    func hasUncommittedChanges() -> Bool

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

    /// Returns true if there is an alternative store in the checkout and it is valid.
    func isAlternateObjectStoreValid(expected: AbsolutePath) -> Bool

    /// Returns true if the file at `path` is ignored by `git`
    func areIgnored(_ paths: [AbsolutePath]) throws -> [Bool]
}

/// A single repository revision.
public struct Revision: Hashable {
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

public protocol FetchProgress {
    typealias Handler = (FetchProgress) -> Void

    var message: String { get }
    var step: Int { get }
    var totalSteps: Int? { get }
    /// The current download progress including the unit
    var downloadProgress: String? { get }
    /// The current download speed including the unit
    var downloadSpeed: String? { get }
}
