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
import Dispatch
import Foundation
import SourceControl

import struct TSCBasic.ByteString
import enum TSCBasic.FileMode
import struct TSCBasic.FileSystemError

/// The error encountered during in memory git repository operations.
package enum InMemoryGitRepositoryError: Swift.Error {
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
package final class InMemoryGitRepository {
    /// The revision identifier.
    package typealias RevisionIdentifier = String

    /// A struct representing a revision state. Minimally it contains a hash identifier for the revision
    /// and the file system state.
    fileprivate struct RevisionState {
        /// The revision identifier hash. It should be unique among all the identifiers.
        var hash: RevisionIdentifier

        /// The filesystem state contained in this revision.
        let fileSystem: InMemoryFileSystem

        /// Creates copy of the state.
        func copy() -> RevisionState {
            return RevisionState(hash: self.hash, fileSystem: self.fileSystem.copy())
        }
    }

    /// THe HEAD i.e. the current checked out state.
    fileprivate var head: RevisionState

    /// The history dictionary.
    fileprivate var history: [RevisionIdentifier: RevisionState] = [:]

    /// The map containing tag name to revision identifier values.
    fileprivate var tagsMap: [String: RevisionIdentifier] = [:]

    /// Indicates whether there are any uncommitted changes in the repository.
    fileprivate var isDirty = false

    /// The path at which this repository is located.
    fileprivate let path: AbsolutePath

    /// The file system in which this repository should be installed.
    private let fs: InMemoryFileSystem

    private let lock = NSLock()

    /// Create a new repository at the given path and filesystem.
    package init(path: AbsolutePath, fs: InMemoryFileSystem) {
        self.path = path
        self.fs = fs
        // Point head to a new revision state with empty hash to begin with.
        self.head = RevisionState(hash: "", fileSystem: InMemoryFileSystem())
    }

    /// The array of current tags in the repository.
    package func getTags() throws -> [String] {
        self.lock.withLock {
            Array(self.tagsMap.keys)
        }
    }

    /// The list of revisions in the repository.
    package var revisions: [RevisionIdentifier] {
        self.lock.withLock {
            Array(self.history.keys)
        }
    }

    /// Copy/clone this repository.
    fileprivate func copy(at newPath: AbsolutePath? = nil)  throws -> InMemoryGitRepository {
        let path = newPath ?? self.path
        try self.fs.createDirectory(path, recursive: true)
        let repo = InMemoryGitRepository(path: path, fs: self.fs)
        self.lock.withLock {
            for (revision, state) in self.history {
                repo.history[revision] = state.copy()
            }
            repo.tagsMap = self.tagsMap
            repo.head = self.head.copy()
        }
        return repo
    }

    /// Commits the current state of the repository filesystem and returns the commit identifier.
    @discardableResult
    package func commit(hash: String? = nil) throws -> String {
        // Create a fake hash for this commit.
        let hash = hash ?? String((UUID().uuidString + UUID().uuidString).prefix(40))
        self.lock.withLock {
            self.head.hash = hash
            // Store the commit in history.
            self.history[hash] = head.copy()
            // We are not dirty anymore.
            self.isDirty = false
        }
        // Install the current HEAD i.e. this commit to the filesystem that was passed.
        try installHead()
        return hash
    }

    /// Checks out the provided revision.
    package func checkout(revision: RevisionIdentifier) throws {
        guard let state = (self.lock.withLock { history[revision] }) else {
            throw InMemoryGitRepositoryError.unknownRevision
        }
        // Point the head to the revision state.
        self.lock.withLock {
            self.head = state
            self.isDirty = false
        }
        // Install this state on the passed filesystem.
        try self.installHead()
    }

    /// Checks out a given tag.
    package func checkout(tag: String) throws {
        guard let hash = (self.lock.withLock { tagsMap[tag] }) else {
            throw InMemoryGitRepositoryError.unknownTag
        }
        // Point the head to the revision state of the tag.
        // It should be impossible that a tag exists which does not have a state.
        try self.lock.withLock {
            guard let head = history[hash] else {
                throw InternalError("unknown hash \(hash)")
            }
            self.head = head
            self.isDirty = false
        }
        // Install this state on the passed filesystem.
        try self.installHead()
    }

    /// Installs (or checks out) current head on the filesystem on which this repository exists.
    fileprivate func installHead() throws {
        // Remove the old state.
        try self.fs.removeFileTree(self.path)
        // Create the repository directory.
        try self.fs.createDirectory(self.path, recursive: true)
        // Get the file system state at the HEAD,
        let headFs = self.lock.withLock { self.head.fileSystem }

        /// Recursively copies the content at HEAD to fs.
        func install(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
            assert(headFs.isDirectory(sourcePath))
            for entry in try headFs.getDirectoryContents(sourcePath) {
                // The full path of the entry.
                let sourceEntryPath = sourcePath.appending(component: entry)
                let destinationEntryPath = destinationPath.appending(component: entry)
                if headFs.isFile(sourceEntryPath) {
                    // If we have a file just write the file.
                    let bytes = try headFs.readFileContents(sourceEntryPath)
                    try self.fs.writeFileContents(destinationEntryPath, bytes: bytes)
                } else if headFs.isDirectory(sourceEntryPath) {
                    // If we have a directory, create that directory and copy its contents.
                    try self.fs.createDirectory(destinationEntryPath, recursive: false)
                    try install(from: sourceEntryPath, to: destinationEntryPath)
                }
            }
        }
        // Install at the repository path.
        try install(from: .root, to: path)
    }

    /// Tag the current HEAD with the given name.
    package func tag(name: String) throws {
        guard (self.lock.withLock { self.tagsMap[name] }) == nil else {
            throw InMemoryGitRepositoryError.tagAlreadyPresent
        }
        self.lock.withLock {
            self.tagsMap[name] = self.head.hash
        }
    }

    package func hasUncommittedChanges() -> Bool {
        self.lock.withLock {
            isDirty
        }
    }

    package func fetch() throws {
        // TODO.
    }
}

extension InMemoryGitRepository: FileSystem {
    package func exists(_ path: TSCAbsolutePath, followSymlink: Bool) -> Bool {
        self.lock.withLock {
            self.head.fileSystem.exists(path, followSymlink: followSymlink)
        }
    }

    package func isDirectory(_ path: TSCAbsolutePath) -> Bool {
        self.lock.withLock {
            self.head.fileSystem.isDirectory(path)
        }
    }

    package func isFile(_ path: TSCAbsolutePath) -> Bool {
        self.lock.withLock {
            self.head.fileSystem.isFile(path)
        }
    }

    package func isSymlink(_ path: TSCAbsolutePath) -> Bool {
        self.lock.withLock {
            self.head.fileSystem.isSymlink(path)
        }
    }

    package func isExecutableFile(_ path: TSCAbsolutePath) -> Bool {
        self.lock.withLock {
            self.head.fileSystem.isExecutableFile(path)
        }
    }

    package func isReadable(_ path: TSCAbsolutePath) -> Bool {
        return self.exists(path)
    }

    package func isWritable(_ path: TSCAbsolutePath) -> Bool {
        return false
    }

    package var currentWorkingDirectory: TSCAbsolutePath? {
        return .root
    }

    package func changeCurrentWorkingDirectory(to path: TSCAbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    package var homeDirectory: TSCAbsolutePath {
        fatalError("Unsupported")
    }

    package var cachesDirectory: TSCAbsolutePath? {
        fatalError("Unsupported")
    }

    package var tempDirectory: TSCAbsolutePath {
        fatalError("Unsupported")
    }

    package func getDirectoryContents(_ path: TSCAbsolutePath) throws -> [String] {
        try self.lock.withLock {
            try self.head.fileSystem.getDirectoryContents(path)
        }
    }

    package func createDirectory(_ path: TSCAbsolutePath, recursive: Bool) throws {
        try self.lock.withLock {
            try self.head.fileSystem.createDirectory(path, recursive: recursive)
        }
    }
    
    package func createSymbolicLink(_ path: TSCAbsolutePath, pointingAt destination: TSCAbsolutePath, relative: Bool) throws {
        throw FileSystemError(.unsupported, path)
    }

    package func readFileContents(_ path: TSCAbsolutePath) throws -> ByteString {
        try self.lock.withLock {
            return try head.fileSystem.readFileContents(path)
        }
    }

    package func writeFileContents(_ path: TSCAbsolutePath, bytes: ByteString) throws {
        try self.lock.withLock {
            try self.head.fileSystem.writeFileContents(path, bytes: bytes)
            self.isDirty = true
        }
    }

    package func removeFileTree(_ path: TSCAbsolutePath) throws {
        try self.lock.withLock {
            try self.head.fileSystem.removeFileTree(path)
        }
    }

    package func chmod(_ mode: FileMode, path: TSCAbsolutePath, options: Set<FileMode.Option>) throws {
        try self.lock.withLock {
            try self.head.fileSystem.chmod(mode, path: path, options: options)
        }
    }

    package func copy(from sourcePath: TSCAbsolutePath, to destinationPath: TSCAbsolutePath) throws {
        try self.lock.withLock {
            try self.head.fileSystem.copy(from: sourcePath, to: destinationPath)
        }
    }

    package func move(from sourcePath: TSCAbsolutePath, to destinationPath: TSCAbsolutePath) throws {
        try self.lock.withLock {
            try self.head.fileSystem.move(from: sourcePath, to: destinationPath)
        }
    }
}

extension InMemoryGitRepository: Repository {
    package func resolveRevision(tag: String) throws -> Revision {
        try self.lock.withLock {
            guard let revision = self.tagsMap[tag] else {
                throw InternalError("unknown tag \(tag)")
            }
            return Revision(identifier: revision)
        }
    }

    package func resolveRevision(identifier: String) throws -> Revision {
        self.lock.withLock {
            return Revision(identifier: self.tagsMap[identifier] ?? identifier)
        }
    }

    package func exists(revision: Revision) -> Bool {
        self.lock.withLock {
            return self.history[revision.identifier] != nil
        }
    }

    package func openFileView(revision: Revision) throws -> FileSystem {
        try self.lock.withLock {
            guard let entry = self.history[revision.identifier] else {
                throw InternalError("unknown revision \(revision)")
            }
            return entry.fileSystem
        }
    }

    package func openFileView(tag: String) throws -> FileSystem {
        let revision = try self.resolveRevision(tag: tag)
        return try self.openFileView(revision: revision)
    }
}

extension InMemoryGitRepository: WorkingCheckout {
    package func getCurrentRevision() throws -> Revision {
        self.lock.withLock {
            return Revision(identifier: self.head.hash)
        }
    }

    package func checkout(revision: Revision) throws {
        // will lock
        try checkout(revision: revision.identifier)
    }

    package func hasUnpushedCommits() throws -> Bool {
        return false
    }

    package func checkout(newBranch: String) throws {
        self.lock.withLock {
            self.history[newBranch] = head
        }
    }

    package func isAlternateObjectStoreValid(expected: AbsolutePath) -> Bool {
        return true
    }

    package func areIgnored(_ paths: [AbsolutePath]) throws -> [Bool] {
        return [false]
    }
}

// package mutation of `InMemoryGitRepository` is protected with a lock.
extension InMemoryGitRepository: @unchecked Sendable {}

/// This class implement provider for in memory git repository.
package final class InMemoryGitRepositoryProvider: RepositoryProvider {
    /// Contains the repository added to this provider.
    package var specifierMap = ThreadSafeKeyValueStore<RepositorySpecifier, InMemoryGitRepository>()

    /// Contains the repositories which are fetched using this provider.
    package var fetchedMap = ThreadSafeKeyValueStore<AbsolutePath, InMemoryGitRepository>()

    /// Contains the repositories which are checked out using this provider.
    package var checkoutsMap = ThreadSafeKeyValueStore<AbsolutePath, InMemoryGitRepository>()

    /// Create a new provider.
    package init() {
    }

    /// Add a repository to this provider. Only the repositories added with this interface can be operated on
    /// with this provider.
    package func add(specifier: RepositorySpecifier, repository: InMemoryGitRepository) {
        // Save the repository in specifier map.
        specifierMap[specifier] = repository
    }

    /// This method returns the stored reference to the git repository which was fetched or checked out.
    package func openRepo(at path: AbsolutePath) throws -> InMemoryGitRepository {
        if let fetch = fetchedMap[path] {
            return fetch
        }
        guard let checkout = checkoutsMap[path] else {
            throw InternalError("unknown repo at \(path)")
        }
        return checkout
    }

    // MARK: - RepositoryProvider conformance
    // Note: These methods use force unwrap (instead of throwing) to honor their preconditions.

    package func fetch(repository: RepositorySpecifier, to path: AbsolutePath, progressHandler: FetchProgress.Handler? = nil) throws {
        guard let repo = specifierMap[RepositorySpecifier(location: repository.location)] else {
            throw InternalError("unknown repo at \(repository.location)")
        }
        fetchedMap[path] = try repo.copy()
        add(specifier: RepositorySpecifier(path: path), repository: repo)
    }

    package func repositoryExists(at path: AbsolutePath) throws -> Bool {
        return fetchedMap[path] != nil
    }

    package func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        guard let repo = fetchedMap[sourcePath] else {
            throw InternalError("unknown repo at \(sourcePath)")
        }
        fetchedMap[destinationPath] = try repo.copy()
    }

    package func open(repository: RepositorySpecifier, at path: AbsolutePath) throws -> Repository {
        guard let repository = self.fetchedMap[path] else {
            throw InternalError("unknown repository at \(path)")
        }
        return repository
    }

    package func createWorkingCopy(
        repository: RepositorySpecifier,
        sourcePath: AbsolutePath,
        at destinationPath: AbsolutePath,
        editable: Bool
    ) throws -> WorkingCheckout {
        guard let checkout = fetchedMap[sourcePath] else {
            throw InternalError("unknown checkout at \(sourcePath)")
        }
        let copy = try checkout.copy(at: destinationPath)
        checkoutsMap[destinationPath] = copy
        return copy
    }

    package func workingCopyExists(at path: AbsolutePath) throws -> Bool {
        return checkoutsMap.contains(path)
    }

    package func openWorkingCopy(at path: AbsolutePath) throws -> WorkingCheckout {
        guard let checkout = checkoutsMap[path] else {
            throw InternalError("unknown checkout at \(path)")
        }
        return checkout
    }

    package func isValidDirectory(_ directory: AbsolutePath) throws -> Bool {
        return true
    }

    package func isValidDirectory(_ directory: AbsolutePath, for repository: RepositorySpecifier) throws -> Bool {
        return true
    }

    package func cancel(deadline: DispatchTime) throws {
        // noop
    }
}
