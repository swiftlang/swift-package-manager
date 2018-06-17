/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Dispatch
import Utility
import SPMGit

struct InvalidTagError: Error {
    let tag: String
}

/// A `git` repository provider against the libgit library.
public class LibraryGitRepositoryProvider: RepositoryProvider {
    public func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // Perform a bare clone.
        //
        // NOTE: We intentionally do not create a shallow clone here; the
        // expected cost of iterative updates on a full clone is less than on a
        // shallow clone.

        precondition(!exists(path))

        // FIXME: We need infrastructure in this subsystem for reporting
        // status information.

        try SPMGit.Repository.clone(from: repository.url, to: path)
    }

    public func open(repository: RepositorySpecifier, at path: AbsolutePath) -> Repository {
        return try! LibraryGitRepository(SPMGit.Repository(path: path))
    }

    public func cloneCheckout(
        repository: RepositorySpecifier,
        at sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        editable: Bool
    ) throws {
    }

    public func checkoutExists(at path: AbsolutePath) throws -> Bool {
        return true
    }

    public func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        return try! LibraryGitRepository(SPMGit.Repository(path: path))
    }
}

/// A basic `git` repository. This class is thread safe.
//
// FIXME: Currently, this class is serving two goals, it is the Repository
// interface used by `RepositoryProvider`, but is also a class which can be
// instantiated directly against non-RepositoryProvider controlled
// repositories. This may prove inconvenient if what is currently `Repository`
// becomes inconvenient or incompatible with the ideal interface for this
// class. It is possible we should rename `Repository` to something more
// abstract, and change the provider to just return an adaptor around this
// class.
public class LibraryGitRepository: Repository, WorkingCheckout {
    public var tags: [String] {
        return queue.sync {
            try! repository.listTagNames()
        }
    }

    /// The SPMGit repository.
    private let repository: SPMGit.Repository

    /// The (serial) queue to execute git operations on.
    private let queue = DispatchQueue(label: "org.swift.swiftpm.gitlib")

    internal init(_ repository: SPMGit.Repository) {
        self.repository = repository
    }

    public func resolveRevision(tag tagName: String) throws -> Revision {
        guard let tag = try repository.getTags().first(where: { $0.name == tagName }) else {
            throw InvalidTagError(tag: tagName)
        }

        return Revision(identifier: tag.identifier.hexadecimalRepresentation)
    }

    public func resolveRevision(identifier: String) throws -> Revision {
        return Revision(identifier: try repository
            .resolveReference(fromName: identifier)
            .hexadecimalRepresentation)
    }

    public func fetch() throws {
    }

    public func exists(revision: Revision) -> Bool {
        return false
    }

    public func openFileView(revision: Revision) throws -> FileSystem {
        return localFileSystem
    }

    public func getCurrentRevision() throws -> Revision {
        return Revision(identifier: "")
    }

    public func hasUnpushedCommits() throws -> Bool {
        return false
    }

    public func hasUncommittedChanges() -> Bool {
        return false
    }

    public func checkout(tag: String) throws {
    }

    public func checkout(revision: Revision) throws {
    }

    public func checkout(newBranch: String) throws {
    }

    public func isAlternateObjectStoreValid() -> Bool {
        return false
    }

    public func areIgnored(_ paths: [AbsolutePath]) throws -> [Bool] {
        return []
    }
}
