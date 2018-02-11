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

public enum GitRepositoryProviderError: Swift.Error {
    case gitCloneFailure(errorOutput: String)
}

/// A `git` repository provider.
public class GitRepositoryProvider: RepositoryProvider {

    /// Reference to process set, if installed.
    private let processSet: ProcessSet?

    public init(processSet: ProcessSet? = nil) {
        self.processSet = processSet
    }

    public func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // Perform a bare clone.
        //
        // NOTE: We intentionally do not create a shallow clone here; the
        // expected cost of iterative updates on a full clone is less than on a
        // shallow clone.

        precondition(!exists(path))

        // FIXME: We need infrastructure in this subsystem for reporting
        // status information.

        let process = Process(
            args: Git.tool, "clone", "--mirror", repository.url, path.asString, environment: Git.environment)
        // Add to process set.
        try processSet?.add(process)
        // Launch the process.
        try process.launch()
        // Block until cloning completes.
        let result = try process.waitUntilExit()
        // Throw if cloning failed.
        guard result.exitStatus == .terminated(code: 0) else {
            let errorOutput = try (result.utf8Output() + result.utf8stderrOutput()).chuzzle() ?? ""
            throw GitRepositoryProviderError.gitCloneFailure(errorOutput: errorOutput)
        }
    }

    public func open(repository: RepositorySpecifier, at path: AbsolutePath) -> Repository {
        return GitRepository(path: path, isWorkingRepo: false)
    }

    public func cloneCheckout(
        repository: RepositorySpecifier,
        at sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        editable: Bool
    ) throws {

        if editable {
            // For editable clones, i.e. the user is expected to directly work on them, first we create
            // a clone from our cache of repositories and then we replace the remote to the one originally
            // present in the bare repository.
            try Process.checkNonZeroExit(args:
                    Git.tool, "clone", sourcePath.asString, destinationPath.asString)
            // The default name of the remote.
            let origin = "origin"
            // In destination repo remove the remote which will be pointing to the source repo.
            let clone = GitRepository(path: destinationPath)
            // Set the original remote to the new clone.
            try clone.setURL(remote: origin, url: repository.url)
            // FIXME: This is unfortunate that we have to fetch to update remote's data.
            try clone.fetch()
        } else {
            // Clone using a shared object store with the canonical copy.
            //
            // We currently expect using shared storage here to be safe because we
            // only ever expect to attempt to use the working copy to materialize a
            // revision we selected in response to dependency resolution, and if we
            // re-resolve such that the objects in this repository changed, we would
            // only ever expect to get back a revision that remains present in the
            // object storage.
            try Process.checkNonZeroExit(args:
                    Git.tool, "clone", "--shared", sourcePath.asString, destinationPath.asString)
        }
    }

    public func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        return GitRepository(path: path)
    }
}

enum GitInterfaceError: Swift.Error {
    /// This indicates a problem communicating with the `git` tool.
    case malformedResponse(String)
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
public class GitRepository: Repository, WorkingCheckout {
    /// A hash object.
    struct Hash: Equatable, Hashable {
        // FIXME: We should optimize this representation.
        let bytes: ByteString

        /// Create a hash from the given hexadecimal representation.
        ///
        /// - Returns; The hash, or nil if the identifier is invalid.
        init?(_ identifier: String) {
            self.init(asciiBytes: ByteString(encodingAsUTF8: identifier).contents)
        }

        /// Create a hash from the given ASCII bytes.
        ///
        /// - Returns; The hash, or nil if the identifier is invalid.
        init?<C: Collection>(asciiBytes bytes: C) where C.Iterator.Element == UInt8 {
            if bytes.count != 40 {
                return nil
            }
            for byte in bytes {
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"),
                     UInt8(ascii: "a")...UInt8(ascii: "z"):
                    continue
                default:
                    return nil
                }
            }
            self.bytes = ByteString(bytes)
        }

        public var hashValue: Int {
            return bytes.hashValue
        }
    }

    /// A commit object.
    struct Commit: Equatable {
        /// The object hash.
        let hash: Hash

        /// The tree contained in the commit.
        let tree: Hash
    }

    /// A tree object.
    struct Tree {
        struct Entry {
            enum EntryType {
                case blob
                case commit
                case executableBlob
                case symlink
                case tree

                init?(mode: Int) {
                    // Although the mode is a full UNIX mode mask, there are
                    // only a limited set of allowed values.
                    switch mode {
                    case 0o040000:
                        self = .tree
                    case 0o100644:
                        self = .blob
                    case 0o100755:
                        self = .executableBlob
                    case 0o120000:
                        self = .symlink
                    case 0o160000:
                        self = .commit
                    default:
                        return nil
                    }
                }
            }

            /// The hash of the object.
            let hash: Hash

            /// The type of object referenced.
            let type: EntryType

            /// The name of the object.
            let name: String
        }

        /// The object hash.
        let hash: Hash

        /// The list of contents.
        let contents: [Entry]
    }

    /// The path of the repository on disk.
    public let path: AbsolutePath

    /// The (serial) queue to execute git cli on.
    private let queue = DispatchQueue(label: "org.swift.swiftpm.gitqueue")

    /// If this repo is a work tree repo (checkout) as opposed to a bare repo.
    let isWorkingRepo: Bool

    public init(path: AbsolutePath, isWorkingRepo: Bool = true) {
        self.path = path
        self.isWorkingRepo = isWorkingRepo
        do {
            let isBareRepo = try Process.checkNonZeroExit(
                    args: Git.tool, "-C", path.asString, "rev-parse", "--is-bare-repository").chomp() == "true"
            assert(isBareRepo != isWorkingRepo)
        } catch {
            // Ignore if we couldn't run popen for some reason.
        }
    }

    /// Changes URL for the remote.
    ///
    /// - parameters:
    ///   - remote: The name of the remote to operate on. It should already be present.
    ///   - url: The new url of the remote.
    func setURL(remote: String, url: String) throws {
        try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "remote", "set-url", remote, url)
            return
        }
    }

    /// Gets the current list of remotes of the repository.
    ///
    /// - Returns: An array of tuple containing name and url of the remote.
    public func remotes() throws -> [(name: String, url: String)] {
        return try queue.sync {
            // Get the remote names.
            let remoteNamesOutput = try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "remote").chomp()
            let remoteNames = remoteNamesOutput.split(separator: "\n").map(String.init)
            return try remoteNames.map({ name in
                // For each remote get the url.
                let url = try Process.checkNonZeroExit(
                    args: Git.tool, "-C", path.asString, "config", "--get", "remote.\(name).url").chomp()
                return (name, url)
            })
        }
    }

    // MARK: Repository Interface

    /// Returns the tags present in repository.
    public var tags: [String] {
        return queue.sync {
            // Check if we already have the tags cached.
            if let tags = tagsCache {
                return tags
            }
            tagsCache = getTags()
            return tagsCache!
        }
    }

    /// Cache for the tags.
    private var tagsCache: [String]?

    /// Returns the tags present in repository.
    private func getTags() -> [String] {
        // FIXME: Error handling.
        let tagList = try! Process.checkNonZeroExit(
            args: Git.tool, "-C", path.asString, "tag", "-l").chomp()
        return tagList.split(separator: "\n").map(String.init)
    }

    public func resolveRevision(tag: String) throws -> Revision {
        return try Revision(identifier: resolveHash(treeish: tag, type: "commit").bytes.asString!)
    }

    public func resolveRevision(identifier: String) throws -> Revision {
        return try Revision(identifier: resolveHash(treeish: identifier, type: "commit").bytes.asString!)
    }

    public func fetch() throws {
        try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "remote", "update", "-p", environment: Git.environment)
            self.tagsCache = nil
        }
    }

    public func hasUncommittedChanges() -> Bool {
        // Only a work tree can have changes.
        guard isWorkingRepo else { return false }
        return queue.sync {
            // Check nothing has been changed
            guard let result = try? Process.checkNonZeroExit(args: Git.tool, "-C", path.asString, "status", "-s") else {
                return false
            }
            return !result.chomp().isEmpty
        }
    }

    public func openFileView(revision: Revision) throws -> FileSystem {
        return try GitFileSystemView(repository: self, revision: revision)
    }

    // MARK: Working Checkout Interface

    public func hasUnpushedCommits() throws -> Bool {
        return try queue.sync {
            let hasOutput = try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "log", "--branches", "--not", "--remotes").chomp().isEmpty
            return !hasOutput
        }
    }

    public func getCurrentRevision() throws -> Revision {
        return try queue.sync {
            return try Revision(
                identifier: Process.checkNonZeroExit(
                    args: Git.tool, "-C", path.asString, "rev-parse", "--verify", "HEAD").chomp())
        }
    }

    public func checkout(tag: String) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "reset", "--hard", tag)
            try self.updateSubmoduleAndClean()
        }
    }

    public func checkout(revision: Revision) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "checkout", "-f", revision.identifier)
            try self.updateSubmoduleAndClean()
        }
    }

    /// Initializes and updates the submodules, if any, and cleans left over the files and directories using git-clean.
    private func updateSubmoduleAndClean() throws {
        try Process.checkNonZeroExit(args: Git.tool,
            "-C", path.asString, "submodule", "update", "--init", "--recursive", environment: Git.environment)
        try Process.checkNonZeroExit(args: Git.tool,
            "-C", path.asString, "clean", "-ffdx")
    }

    /// Returns true if a revision exists.
    public func exists(revision: Revision) -> Bool {
        return queue.sync {
            let result = try? Process.popen(
                args: Git.tool, "-C", path.asString, "rev-parse", "--verify", revision.identifier)
            return result?.exitStatus == .terminated(code: 0)
        }
    }

    public func checkout(newBranch: String) throws {
        precondition(isWorkingRepo, "This operation should run in a working repo.")
        try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "checkout", "-b", newBranch)
            return
        }
    }

    /// Returns true if there is an alternative object store in the repository and it is valid.
    public func isAlternateObjectStoreValid() -> Bool {
        let objectStoreFile = path.appending(components: ".git", "objects", "info", "alternates")
        guard let bytes = try? localFileSystem.readFileContents(objectStoreFile) else {
            return false
        }
        let split = bytes.contents.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: false)
        guard let firstLine = ByteString(split[0]).asString else {
            return false
        }
        return localFileSystem.isDirectory(AbsolutePath(firstLine))
    }

    // MARK: Git Operations

    /// Resolve a "treeish" to a concrete hash.
    ///
    /// Technically this method can accept much more than a "treeish", it maps
    /// to the syntax accepted by `git rev-parse`.
    func resolveHash(treeish: String, type: String? = nil) throws -> Hash {
        let specifier: String
        if let type = type {
            specifier = treeish + "^{\(type)}"
        } else {
            specifier = treeish
        }
        let response = try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "rev-parse", "--verify", specifier).chomp()
        }
        if let hash = Hash(response) {
            return hash
        } else {
            throw GitInterfaceError.malformedResponse("expected an object hash in \(response)")
        }
    }

    /// Read the commit referenced by `hash`.
    func read(commit hash: Hash) throws -> Commit {
        // Currently, we just load the tree, using the typed `rev-parse` syntax.
        let treeHash = try resolveHash(treeish: hash.bytes.asString!, type: "tree")

        return Commit(hash: hash, tree: treeHash)
    }

    /// Read a tree object.
    func read(tree hash: Hash) throws -> Tree {
        // Get the contents using `ls-tree`.
        let treeInfo = try queue.sync {
            try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "ls-tree", hash.bytes.asString!)
        }

        var contents: [Tree.Entry] = []
        for line in treeInfo.components(separatedBy: "\n") {
            // Ignore empty lines.
            if line == "" { continue }

            // Each line in the response should match:
            //
            //   `mode type hash\tname`
            //
            // where `mode` is the 6-byte octal file mode, `type` is a 4-byte or 6-byte
            // type ("blob", "tree", "commit"), `hash` is the hash, and the remainder of
            // the line is the file name.
            let bytes = ByteString(encodingAsUTF8: line)
            let expectedBytesCount = 6 + 1 + 4 + 1 + 40 + 1
            guard bytes.count > expectedBytesCount,
                  bytes.contents[6] == UInt8(ascii: " "),
                  // Search for the second space since `type` is of variable length.
                  let secondSpace = bytes.contents[6 + 1 ..< bytes.contents.endIndex].index(of: UInt8(ascii: " ")),
                  bytes.contents[secondSpace] == UInt8(ascii: " "),
                  bytes.contents[secondSpace + 1 + 40] == UInt8(ascii: "\t") else {
                throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(treeInfo)'")
            }

            // Compute the mode.
            let mode = bytes.contents[0..<6].reduce(0) { (acc: Int, char: UInt8) in
                (acc << 3) | (Int(char) - Int(UInt8(ascii: "0")))
            }
            guard let type = Tree.Entry.EntryType(mode: mode),
                  let hash = Hash(asciiBytes: bytes.contents[(secondSpace + 1)..<(secondSpace + 1 + 40)]),
                  let name = ByteString(bytes.contents[(secondSpace + 1 + 40 + 1)..<bytes.count]).asString else {
                throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(treeInfo)'")
            }

            // FIXME: We do not handle de-quoting of names, currently.
            if name.hasPrefix("\"") {
                throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(treeInfo)'")
            }

            contents.append(Tree.Entry(hash: hash, type: type, name: name))
        }

        return Tree(hash: hash, contents: contents)
    }

    /// Read a blob object.
    func read(blob hash: Hash) throws -> ByteString {
        return try queue.sync {
            // Get the contents using `cat-file`.
            //
            // FIXME: We need to get the raw bytes back, not a String.
            let output = try Process.checkNonZeroExit(
                args: Git.tool, "-C", path.asString, "cat-file", "-p", hash.bytes.asString!)
            return ByteString(encodingAsUTF8: output)
        }
    }
}

func == (_ lhs: GitRepository.Commit, _ rhs: GitRepository.Commit) -> Bool {
    return lhs.hash == rhs.hash && lhs.tree == rhs.tree
}

func == (_ lhs: GitRepository.Hash, _ rhs: GitRepository.Hash) -> Bool {
    return lhs.bytes == rhs.bytes
}

/// A `git` file system view.
///
/// The current implementation is based on lazily caching data with no eviction
/// policy, and is very unoptimized.
private class GitFileSystemView: FileSystem {
    typealias Hash = GitRepository.Hash
    typealias Tree = GitRepository.Tree

    // MARK: Git Object Model

    // The map of loaded trees.
    var trees: [Hash: Tree] = [:]

    /// The underlying repository.
    let repository: GitRepository

    /// The revision this is a view on.
    let revision: Revision

    /// The root tree hash.
    let root: GitRepository.Hash

    init(repository: GitRepository, revision: Revision) throws {
        self.repository = repository
        self.revision = revision
        self.root = try repository.read(commit: Hash(revision.identifier)!).tree
    }

    // MARK: FileSystem Implementation

    private func getEntry(_ path: AbsolutePath) throws -> Tree.Entry? {
        // Walk the components resolving the tree (starting with a synthetic
        // root entry).
        var current: Tree.Entry = Tree.Entry(hash: root, type: .tree, name: "/")
        for component in path.components.dropFirst(1) {
            // Skip the root pseudo-component.
            if component == "/" { continue }

            // We have a component to resolve, so the current entry must be a tree.
            guard current.type == .tree else {
                throw FileSystemError.notDirectory
            }

            // Fetch the tree.
            let tree = try getTree(current.hash)

            // Search the tree for the component.
            //
            // FIXME: This needs to be optimized, somewhere.
            guard let index = tree.contents.index(where: { $0.name == component }) else {
                return nil
            }

            current = tree.contents[index]
        }

        return current
    }

    private func getTree(_ hash: Hash) throws -> Tree {
        // Check the cache.
        if let tree = trees[hash] {
            return tree
        }

        // Otherwise, load it.
        let tree = try repository.read(tree: hash)
        trees[hash] = tree
        return tree
    }

    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        do {
            return try getEntry(path) != nil
        } catch {
            return false
        }
    }

    func isFile(_ path: AbsolutePath) -> Bool {
        do {
            if let entry = try getEntry(path), entry.type != .tree {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    func isDirectory(_ path: AbsolutePath) -> Bool {
        do {
            if let entry = try getEntry(path), entry.type == .tree {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    func isSymlink(_ path: AbsolutePath) -> Bool {
        do {
            if let entry = try getEntry(path), entry.type == .symlink {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    func isExecutableFile(_ path: AbsolutePath) -> Bool {
        if let entry = try? getEntry(path), entry?.type == .executableBlob {
            return true
        }
        return false
    }

    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        guard let entry = try getEntry(path) else {
            throw FileSystemError.noEntry
        }
        guard entry.type == .tree else {
            throw FileSystemError.notDirectory
        }

        return try getTree(entry.hash).contents.map({ $0.name })
    }

    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        guard let entry = try getEntry(path) else {
            throw FileSystemError.noEntry
        }
        guard entry.type != .tree else {
            throw FileSystemError.isDirectory
        }
        guard entry.type != .symlink else {
            fatalError("FIXME: not implemented")
        }
        return try repository.read(blob: entry.hash)
    }

    // MARK: Unsupported methods.

    func createDirectory(_ path: AbsolutePath) throws {
        throw FileSystemError.unsupported
    }

    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        throw FileSystemError.unsupported
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        throw FileSystemError.unsupported
    }

    func removeFileTree(_ path: AbsolutePath) {
        fatalError("unsupported")
    }

    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        throw FileSystemError.unsupported
    }
}

extension GitRepositoryProviderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .gitCloneFailure(let errorOutput):
            return "failed to clone; \(errorOutput)"
        }
    }
}
