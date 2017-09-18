/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Dispatch
import Utility
import class Foundation.NSUUID

/// The error encountered during in memory git repository operations.
public enum InMemoryGitRepositoryError: Swift.Error {
    case unknownRevision
    case unknownTag
    case tagAlreadyPresent
}

/// A class that implements basic git features on in-memory file system. It takes the path and file system reference
/// where the repository should be created. The class itself is a file system pointing to current revision state
/// i.e. HEAD. All mutations should be made on file system interface of this class and then they can be committed using
/// commit() method. Calls to checkout related methods will checkout the HEAD on the passed file system at the
/// repository path, as well as on the file system interface of this class.
/// Note: This class is intended to be used as testing infrastructure only.
/// Note: This class is not thread safe yet.
public final class InMemoryGitRepository {
    /// The revision identifier.
    public typealias RevisionIdentifier = String

    /// A struct representing a revision state. Minimally it contains a hash identifier for the revision
    /// and the file system state.
    fileprivate struct RevisionState {
        /// The revision identifier hash. It should be unique amoung all the identifiers.
        var hash: RevisionIdentifier

        /// The filesystem state contained in this revision.
        let fileSystem: InMemoryFileSystem

        /// Creates copy of the state.
        func copy() -> RevisionState {
            return RevisionState(hash: hash, fileSystem: fileSystem.copy())
        }
    }

    /// THe HEAD i.e. the current checked out state.
    fileprivate var head: RevisionState

    /// The history dictionary.
    fileprivate var history: [RevisionIdentifier: RevisionState] = [:]

    /// The map containing tag name to revision identifier values.
    fileprivate var tagsMap: [String: RevisionIdentifier] = [:]

    /// The array of current tags in the repository.
    public var tags: [String] {
        return Array(tagsMap.keys)
    }

    /// Indicates whether there are any uncommited changes in the repository.
    fileprivate var isDirty = false

    /// The path at which this repository is located.
    fileprivate let path: AbsolutePath

    /// The file system in which this repository should be installed.
    private let fs: InMemoryFileSystem

    /// Create a new repository at the given path and filesystem.
    public init(path: AbsolutePath, fs: InMemoryFileSystem) {
        self.path = path
        self.fs = fs
        // Point head to a new revision state with empty hash to begin with.
        head = RevisionState(hash: "", fileSystem: InMemoryFileSystem())
    }

    /// Copy/clone this repository.
    fileprivate func copy() -> InMemoryGitRepository {
        let repo = InMemoryGitRepository(path: path, fs: fs)
        for (revision, state) in history {
            repo.history[revision] = state.copy()
        }
        repo.tagsMap = tagsMap
        repo.head = head.copy()
        return repo
    }

    /// Commits the current state of the repository filesystem and returns the commit identifier.
    @discardableResult
    public func commit() -> String {
        // Create a fake hash for thie commit.
        let hash = NSUUID().uuidString
        head.hash = hash
        // Store the commit in history.
        history[hash] = head.copy()
        // We are not dirty anymore.
        isDirty = false
        // Install the current HEAD i.e. this commit to the filesystem that was passed.
        try! installHead()
        return hash
    }

    /// Checks out the provided revision.
    public func checkout(revision: RevisionIdentifier) throws {
        guard let state = history[revision] else {
            throw InMemoryGitRepositoryError.unknownRevision
        }
        // Point the head to the revision state.
        head = state
        isDirty = false
        // Install this state on the passed filesystem.
        try installHead()
    }

    /// Checks out a given tag.
    public func checkout(tag: String) throws {
        guard let hash = tagsMap[tag] else {
            throw InMemoryGitRepositoryError.unknownTag
        }
        // Point the head to the revision state of the tag.
        // It should be impossible that a tag exisits which doesnot have a state.
        head = history[hash]!
        isDirty = false
        // Install this state on the passed filesystem.
        try installHead()
    }

    /// Installs (or checks out) current head on the filesystem on which this repository exists.
    private func installHead() throws {
        // Remove the old state.
        try fs.removeFileTree(path)
        // Create the repository directory.
        try fs.createDirectory(path, recursive: true)
        // Get the file system state at the HEAD,
        let headFs = head.fileSystem

        /// Recursively copies the content at HEAD to fs.
        func install(at path: AbsolutePath) throws {
            for entry in try headFs.getDirectoryContents(path) {
                // The full path of the entry.
                let entryPath = path.appending(component: entry)
                if headFs.isFile(entryPath) {
                    // If we have a file just write the file.
                    try fs.writeFileContents(entryPath, bytes: try headFs.readFileContents(entryPath))
                } else if headFs.isDirectory(entryPath) {
                    // If we have a directory, create that directory and copy its contents.
                    try fs.createDirectory(entryPath, recursive: false)
                    try install(at: entryPath)
                }
            }
        }
        // Install at the repository path.
        try install(at: path)
    }

    /// Tag the current HEAD with the given name.
    public func tag(name: String) throws {
        guard tagsMap[name] == nil else {
            throw InMemoryGitRepositoryError.tagAlreadyPresent
        }
        tagsMap[name] = head.hash
    }

    public func hasUncommitedChanges() -> Bool {
        return isDirty
    }

    public func fetch() throws {
        // TODO.
    }
}

extension InMemoryGitRepository: FileSystem {

    public func exists(_ path: AbsolutePath) -> Bool {
        return head.fileSystem.exists(path)
    }

    public func isDirectory(_ path: AbsolutePath) -> Bool {
        return head.fileSystem.isDirectory(path)
    }

    public func isFile(_ path: AbsolutePath) -> Bool {
        return head.fileSystem.isFile(path)
    }

    public func isSymlink(_ path: AbsolutePath) -> Bool {
        return head.fileSystem.isSymlink(path)
    }

    public func isExecutableFile(_ path: AbsolutePath) -> Bool {
        return head.fileSystem.isExecutableFile(path)
    }

    public func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        return try head.fileSystem.getDirectoryContents(path)
    }

    public func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        try head.fileSystem.createDirectory(path, recursive: recursive)
    }

    public func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        return try head.fileSystem.readFileContents(path)
    }

    public func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        try head.fileSystem.writeFileContents(path, bytes: bytes)
        isDirty = true
    }

    public func removeFileTree(_ path: AbsolutePath) throws {
        try head.fileSystem.removeFileTree(path)
    }

    public func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        try head.fileSystem.chmod(mode, path: path, options: options)
    }
}

extension InMemoryGitRepository: Repository {
    public func resolveRevision(tag: String) throws -> Revision {
        return Revision(identifier: tagsMap[tag]!)
    }

    public func resolveRevision(identifier: String) throws -> Revision {
        fatalError("unimplemented")
    }

    public func exists(revision: Revision) -> Bool {
        return history[revision.identifier] != nil
    }

    public func openFileView(revision: Revision) throws -> FileSystem {
        var fs: FileSystem = history[revision.identifier]!.fileSystem
        return RerootedFileSystemView(&fs, rootedAt: path)
    }
}

extension InMemoryGitRepository: WorkingCheckout {
    public func getCurrentRevision() throws -> Revision {
        return Revision(identifier: head.hash)
    }

    public func checkout(revision: Revision) throws {
        try checkout(revision: revision.identifier)
    }

    public func hasUnpushedCommits() throws -> Bool {
        fatalError("Unimplemented")
    }

    public func checkout(newBranch: String) throws {
        fatalError("Unimplemented")
    }
}

/// This class implement provider for in memeory git repository.
public final class InMemoryGitRepositoryProvider: RepositoryProvider {
    /// Contains the repository added to this provider.
    public private(set) var specifierMap = [RepositorySpecifier: InMemoryGitRepository]()

    /// Contains the repositories which are fetched using this provider.
    private var fetchedMap = [AbsolutePath: InMemoryGitRepository]()

    /// Contains the repositories which are checked out using this provider.
    private var checkoutsMap = [AbsolutePath: InMemoryGitRepository]()

    /// Create a new provider.
    public init() {
    }

    /// Add a repository to this provider. Only the repositories added with this interface can be operated on
    /// with this provider.
    public func add(specifier: RepositorySpecifier, repository: InMemoryGitRepository) {
        // Save the repository in specifer map.
        specifierMap[specifier] = repository
    }

    /// This method returns the stored reference to the git repository which was fetched or checked out.
    public func openRepo(at path: AbsolutePath) -> InMemoryGitRepository {
        return fetchedMap[path] ?? checkoutsMap[path]!
    }

    // MARK: - RepositoryProvider conformance
    // Note: These methods use force unwrap (instead of throwing) to honor their preconditions.

    public func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        fetchedMap[path] = specifierMap[repository]!.copy()
    }

    public func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository {
        return fetchedMap[path]!
    }

    public func cloneCheckout(
        repository: RepositorySpecifier,
        at sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        editable: Bool
    ) throws {
        checkoutsMap[destinationPath] = fetchedMap[sourcePath]!.copy()
    }

    public func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        return checkoutsMap[path]!
    }
}
