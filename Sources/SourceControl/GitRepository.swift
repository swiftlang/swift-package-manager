/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import Dispatch
import TSCUtility

/// A `git` repository provider.
public struct GitRepositoryProvider: RepositoryProvider {

    /// Reference to process set, if installed.
    private let processSet: ProcessSet?

    public init(processSet: ProcessSet? = nil) {
        self.processSet = processSet
    }

    /// Private function to invoke the Git tool with its default environment and given set of arguments.  The specified
    /// failure message is used only in case of error.  This function waits for the invocation to finish and returns the
    /// output as a string.
    @discardableResult
    private func callGit(_ args: String..., environment: [String: String] = Git.environment, failureMessage: String = "", repository: RepositorySpecifier) throws -> String {
        let process = Process(arguments: [Git.tool] + args, environment: environment, outputRedirection: .collect)
        let result: ProcessResult
        do {
            try processSet?.add(process)
            try process.launch()
            result = try process.waitUntilExit()
        }
        catch {
            // Handle a failure to even launch the Git tool by synthesizing a result that we can wrap an error around.
            result = ProcessResult(arguments: process.arguments, environment: process.environment,
                exitStatus: .terminated(code: -1), output: .failure(error), stderrOutput: .failure(error))
        }
        guard result.exitStatus == .terminated(code: 0) else {
            throw GitCloneError(repository: repository, message: failureMessage, result: result)
        }
        return try result.utf8Output()
    }

    public func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // Perform a bare clone.
        //
        // NOTE: We intentionally do not create a shallow clone here; the
        // expected cost of iterative updates on a full clone is less than on a
        // shallow clone.
        precondition(!localFileSystem.exists(path))
        // FIXME: Ideally we should pass `--progress` here and report status regularly.  We currently don't have callbacks for that.
        try callGit("clone", "--mirror", repository.url, path.pathString,
                    failureMessage: "Failed to clone repository \(repository.url)", repository: repository)
    }

    public func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        try localFileSystem.copy(from: sourcePath, to: destinationPath)
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
            try callGit("clone", "--no-checkout", sourcePath.pathString, destinationPath.pathString,
                failureMessage: "Failed to clone repository \(repository.url)", repository: repository)
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
            try callGit("clone", "--shared", "--no-checkout", sourcePath.pathString, destinationPath.pathString,
                failureMessage: "Failed to clone repository \(repository.url)", repository: repository)
        }
    }

    public func checkoutExists(at path: AbsolutePath) throws -> Bool {
        precondition(localFileSystem.exists(path))

        let result = try Process.popen(args: Git.tool, "-C", path.pathString, "rev-parse", "--is-bare-repository")
        return try result.exitStatus == .terminated(code: 0) && result.utf8Output().spm_chomp() == "false"
    }

    public func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        return GitRepository(path: path)
    }
}


public struct GitCloneError: Error, CustomStringConvertible, DiagnosticLocationProviding {
    public let repository: RepositorySpecifier
    public let message: String
    public let result: ProcessResult
    
    public struct Location: DiagnosticLocation {
        public let repository: RepositorySpecifier
        public var description: String {
            return repository.url
        }
    }

    public var diagnosticLocation: DiagnosticLocation? {
        return Location(repository: repository)
    }

    public var description: String {
        let stdout = (try? result.utf8Output()) ?? ""
        let stderr = (try? result.utf8stderrOutput()) ?? ""
        let output = (stdout + stderr).spm_chomp().spm_multilineIndent(count: 4)
        return "\(message):\n\(output)"
    }
}



private enum GitInterfaceError: Swift.Error {
    /// This indicates a problem communicating with the `git` tool.
    case malformedResponse(String)

    /// This indicates that a fatal error was encountered
    case fatalError
}

// FIXME: Currently, this class is serving two goals, it is the Repository
// interface used by `RepositoryProvider`, but is also a class which can be
// instantiated directly against non-RepositoryProvider controlled
// repositories. This may prove inconvenient if what is currently `Repository`
// becomes inconvenient or incompatible with the ideal interface for this
// class. It is possible we should rename `Repository` to something more
// abstract, and change the provider to just return an adaptor around this
// class.
//
/// A basic Git repository in the local file system (almost always a clone of a remote).  This class is thread safe.
public final class GitRepository: Repository, WorkingCheckout {
    /// A hash object.
    public struct Hash: Hashable {
        // FIXME: We should optimize this representation.
        let bytes: ByteString

        /// Create a hash from the given hexadecimal representation.
        ///
        /// - Returns; The hash, or nil if the identifier is invalid.
        public init?(_ identifier: String) {
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
    }

    /// A commit object.
    public struct Commit: Equatable {
        /// The object hash.
        public let hash: Hash

        /// The tree contained in the commit.
        public let tree: Hash
    }

    /// A tree object.
    public struct Tree {
        public struct Entry {
            public enum EntryType {
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
            public let hash: Hash

            /// The type of object referenced.
            public let type: EntryType

            /// The name of the object.
            public let name: String
        }

        /// The object hash.
        public let hash: Hash

        /// The list of contents.
        public let contents: [Entry]
    }

    /// The path of the repository in the local file system.
    public let path: AbsolutePath

    /// Concurrent queue to execute git cli on.
    private let queue = DispatchQueue(label: "org.swift.swiftpm.git", attributes: .concurrent)

    /// If this repo is a work tree repo (checkout) as opposed to a bare repo.
    let isWorkingRepo: Bool
    
    /// Dictionary for memoizing results of git calls that are not expected to change.
    private var cachedHashes = ThreadSafeKeyValueStore<String, Hash>()
    private var cachedBlobs = ThreadSafeKeyValueStore<Hash, ByteString>()
    private var cachedTrees = ThreadSafeKeyValueStore<Hash, Tree>()
    private var cachedTags = ThreadSafeBox<[String]>()
    
    public init(path: AbsolutePath, isWorkingRepo: Bool = true) {
        self.path = path
        self.isWorkingRepo = isWorkingRepo
        do {
            let isBareRepo = try callGit("rev-parse", "--is-bare-repository").spm_chomp() == "true"
            assert(isBareRepo != isWorkingRepo)
        } catch {
            // Ignore if we couldn't run popen for some reason.
        }
    }
    
    /// Private function to invoke the Git tool with its default environment and given set of arguments, specifying the
    /// path of the repository as the one to operate on.  The specified failure message is used only in case of error.
    /// This function waits for the invocation to finish and returns the output as a string.
    @discardableResult
    private func callGit(_ args: String..., environment: [String: String] = Git.environment, failureMessage: String = "") throws -> String {
        let process = Process(arguments: [Git.tool, "-C", path.pathString] + args, environment: environment, outputRedirection: .collect)
        let result: ProcessResult
        do {
            try process.launch()
            result = try process.waitUntilExit()
        }
        catch {
            // Handle a failure to even launch the Git tool by synthesizing a result that we can wrap an error around.
            result = ProcessResult(arguments: process.arguments, environment: process.environment,
                exitStatus: .terminated(code: -1), output: .failure(error), stderrOutput: .failure(error))
        }
        guard result.exitStatus == .terminated(code: 0) else {
            throw GitRepositoryError(path: self.path, message: failureMessage, result: result)
        }
        return try result.utf8Output()
    }

    /// Changes URL for the remote.
    ///
    /// - parameters:
    ///   - remote: The name of the remote to operate on. It should already be present.
    ///   - url: The new url of the remote.
    public func setURL(remote: String, url: String) throws {
        // use barrier for write operations
        try queue.sync(flags: .barrier) {
            try callGit("remote", "set-url", remote, url,
                failureMessage: "Couldn’t set the URL of the remote ‘\(remote)’ to ‘\(url)’")
            return
        }
    }

    /// Gets the current list of remotes of the repository.
    ///
    /// - Returns: An array of tuple containing name and url of the remote.
    public func remotes() throws -> [(name: String, url: String)] {
        return try queue.sync {
            // Get the remote names.
            let remoteNamesOutput = try callGit("remote",
                failureMessage: "Couldn’t get the list of remotes").spm_chomp()
            let remoteNames = remoteNamesOutput.split(separator: "\n").map(String.init)
            return try remoteNames.map({ name in
                // For each remote get the url.
                let url = try callGit("config", "--get", "remote.\(name).url",
                    failureMessage: "Couldn’t get the URL of the remote ‘\(name)’").spm_chomp()
                return (name, url)
            })
        }
    }

    // MARK: Repository Interface

    /// Returns the tags present in repository.
    public func tags() throws -> [String] {
        // Get the contents using `ls-tree`.
        return try queue.sync {
            try self.cachedTags.memoize() {
                let tagList = try callGit("tag", "-l",
                    failureMessage: "Couldn’t get the list of tags").spm_chomp()
                return tagList.split(separator: "\n").map(String.init)
            }
        }
    }

    public func resolveRevision(tag: String) throws -> Revision {
        return try Revision(identifier: resolveHash(treeish: tag, type: "commit").bytes.description)
    }

    public func resolveRevision(identifier: String) throws -> Revision {
        return try Revision(identifier: resolveHash(treeish: identifier, type: "commit").bytes.description)
    }

    public func fetch() throws {
        // use barrier for write operations
        try queue.sync(flags: .barrier) {
            try callGit("remote", "update", "-p",
                failureMessage: "Couldn’t fetch updates from remote repositories")
            self.cachedTags.clear()
        }
    }

    public func hasUncommittedChanges() -> Bool {
        // Only a working repository can have changes.
        guard isWorkingRepo else { return false }
        return queue.sync {
            guard let result = try? callGit("status", "-s") else {
                return false
            }
            return !result.spm_chomp().isEmpty
        }
    }

    public func openFileView(revision: Revision) throws -> FileSystem {
        return try GitFileSystemView(repository: self, revision: revision)
    }

    // MARK: Working Checkout Interface

    public func hasUnpushedCommits() throws -> Bool {
        return try queue.sync {
            let hasOutput = try callGit("log", "--branches", "--not", "--remotes",
                failureMessage: "Couldn’t check for unpushed commits").spm_chomp().isEmpty
            return !hasOutput
        }
    }

    public func getCurrentRevision() throws -> Revision {
        return try queue.sync {
            return try Revision(identifier: callGit("rev-parse", "--verify", "HEAD",
                failureMessage: "Couldn’t get current revision").spm_chomp())
        }
    }

    public func checkout(tag: String) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        // use barrier for write operations
        try queue.sync(flags: .barrier) {
            try callGit("reset", "--hard", tag,
                failureMessage: "Couldn’t check out tag ‘\(tag)’")
            try self.updateSubmoduleAndCleanNotOnQueue()
        }
    }

    public func checkout(revision: Revision) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        // use barrier for write operations
        try queue.sync(flags: .barrier) {
            try callGit("checkout", "-f", revision.identifier,
                failureMessage: "Couldn’t check out revision ‘\(revision.identifier)’")
            try self.updateSubmoduleAndCleanNotOnQueue()
        }
    }

    /// Initializes and updates the submodules, if any, and cleans left over the files and directories using git-clean.
    private func updateSubmoduleAndCleanNotOnQueue() throws {
        try callGit("submodule", "update", "--init", "--recursive",
            failureMessage: "Couldn’t update repository submodules")
        try callGit("clean", "-ffdx",
            failureMessage: "Couldn’t clean repository submodules")
    }

    /// Returns true if a revision exists.
    public func exists(revision: Revision) -> Bool {
        return queue.sync {
            return (try? callGit("rev-parse", "--verify", revision.identifier)) != nil
        }
    }

    public func checkout(newBranch: String) throws {
        precondition(isWorkingRepo, "This operation is only valid in a working repository")
        // use barrier for write operations
        try queue.sync(flags: .barrier) {
            try callGit("checkout", "-b", newBranch,
                failureMessage: "Couldn’t check out new branch ‘\(newBranch)’")
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
        guard let firstLine = ByteString(split[0]).validDescription else {
            return false
        }
        return localFileSystem.isDirectory(AbsolutePath(firstLine))
    }

    /// Returns true if the file at `path` is ignored by `git`
    public func areIgnored(_ paths: [AbsolutePath]) throws -> [Bool] {
        return try queue.sync {
            let stringPaths = paths.map({ $0.pathString })

            return try withTemporaryFile { pathsFile in
                try localFileSystem.writeFileContents(pathsFile.path) {
                    for path in paths {
                        $0 <<< path.pathString <<< "\0"
                    }
                }

                let args = [
                    Git.tool, "-C", self.path.pathString.spm_shellEscaped(),
                    "check-ignore", "-z", "--stdin",
                    "<", pathsFile.path.pathString.spm_shellEscaped()
                ]
                let argsWithSh = ["sh", "-c", args.joined(separator: " ")]
                let result = try Process.popen(arguments: argsWithSh)
                let output = try result.output.get()

                let outputs: [String] = output.split(separator: 0).map({ String(decoding: $0, as: Unicode.UTF8.self) })

                guard result.exitStatus == .terminated(code: 0) || result.exitStatus == .terminated(code: 1) else {
                    throw GitInterfaceError.fatalError
                }
                return stringPaths.map(outputs.contains)
            }
        }
    }

    // MARK: Git Operations

    /// Resolve a "treeish" to a concrete hash.
    ///
    /// Technically this method can accept much more than a "treeish", it maps
    /// to the syntax accepted by `git rev-parse`.
    public func resolveHash(treeish: String, type: String? = nil) throws -> Hash {
        let specifier: String
        if let type = type {
            specifier = treeish + "^{\(type)}"
        } else {
            specifier = treeish
        }
        return try queue.sync {
            try self.cachedHashes.memoize(specifier) {
                let output = try callGit("rev-parse", "--verify", specifier,
                    failureMessage: "Couldn’t get revision ‘\(specifier)’").spm_chomp()
                guard let hash = Hash(output) else {
                    throw GitInterfaceError.malformedResponse("expected an object hash in \(output)")
                }
                return hash
            }
        }
    }

    /// Read the commit referenced by `hash`.
    public func read(commit hash: Hash) throws -> Commit {
        // Currently, we just load the tree, using the typed `rev-parse` syntax.
        let treeHash = try resolveHash(treeish: hash.bytes.description, type: "tree")

        return Commit(hash: hash, tree: treeHash)
    }

    /// Read a tree object.
    public func read(tree hash: Hash) throws -> Tree {
        return try queue.sync {
            try self.cachedTrees.memoize(hash) {
                // Get the contents using `ls-tree`.
                let output = try Process.checkNonZeroExit(
                    args: Git.tool, "-C", self.path.pathString, "ls-tree", hash.bytes.description)
                // construct tree
                var contents: [Tree.Entry] = []
                for line in output.components(separatedBy: "\n") {
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
                          let secondSpace = bytes.contents[6 + 1 ..< bytes.contents.endIndex].firstIndex(of: UInt8(ascii: " ")),
                          bytes.contents[secondSpace] == UInt8(ascii: " "),
                          bytes.contents[secondSpace + 1 + 40] == UInt8(ascii: "\t") else {
                        throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(output)'")
                    }

                    // Compute the mode.
                    let mode = bytes.contents[0..<6].reduce(0) { (acc: Int, char: UInt8) in
                        (acc << 3) | (Int(char) - Int(UInt8(ascii: "0")))
                    }
                    guard let type = Tree.Entry.EntryType(mode: mode),
                          let hash = Hash(asciiBytes: bytes.contents[(secondSpace + 1)..<(secondSpace + 1 + 40)]),
                          let name = ByteString(bytes.contents[(secondSpace + 1 + 40 + 1)..<bytes.count]).validDescription else
                    {
                        throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(output)'")
                    }

                    // FIXME: We do not handle de-quoting of names, currently.
                    if name.hasPrefix("\"") {
                        throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(output)'")
                    }

                    contents.append(Tree.Entry(hash: hash, type: type, name: name))
                }
                return Tree(hash: hash, contents: contents)
            }
        }
    }

    /// Read a blob object.
    func read(blob hash: Hash) throws -> ByteString {
        return try queue.sync {
            try self.cachedBlobs.memoize(hash) {
                // Get the contents using `cat-file`.
                //
                // FIXME: We need to get the raw bytes back, not a String.
                let output = try Process.checkNonZeroExit(
                    args: Git.tool, "-C", path.pathString, "cat-file", "-p", hash.bytes.description)
                return ByteString(encodingAsUTF8: output)
            }
        }
    }
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
        var currentPath = AbsolutePath.root
        for component in path.components.dropFirst(1) {
            // Skip the root pseudo-component.
            if component == "/" { continue }

            currentPath = currentPath.appending(component: component)
            // We have a component to resolve, so the current entry must be a tree.
            guard current.type == .tree else {
                throw FileSystemError(.notDirectory, currentPath)
            }

            // Fetch the tree.
            let tree = try getTree(current.hash)

            // Search the tree for the component.
            //
            // FIXME: This needs to be optimized, somewhere.
            guard let index = tree.contents.firstIndex(where: { $0.name == component }) else {
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
        if let entry = try? getEntry(path), entry.type == .executableBlob {
            return true
        }
        return false
    }

    public var currentWorkingDirectory: AbsolutePath? {
        return AbsolutePath("/")
    }

    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        fatalError("Unsupported")
    }

    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        guard let entry = try getEntry(path) else {
            throw FileSystemError(.noEntry, path)
        }
        guard entry.type == .tree else {
            throw FileSystemError(.notDirectory, path)
        }

        return try getTree(entry.hash).contents.map({ $0.name })
    }

    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        guard let entry = try getEntry(path) else {
            throw FileSystemError(.noEntry, path)
        }
        guard entry.type != .tree else {
            throw FileSystemError(.isDirectory, path)
        }
        guard entry.type != .symlink else {
            fatalError("FIXME: not implemented")
        }
        return try repository.read(blob: entry.hash)
    }

    // MARK: Unsupported methods.

    public var homeDirectory: AbsolutePath {
        fatalError("unsupported")
    }

    public var cachesDirectory: AbsolutePath? {
        fatalError("unsupported")
    }

    func createDirectory(_ path: AbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        throw FileSystemError(.unsupported, path)
    }
    
    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        throw FileSystemError(.unsupported, path)
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        throw FileSystemError(.unsupported, path)
    }

    func removeFileTree(_ path: AbsolutePath) throws {
        throw FileSystemError(.unsupported, path)
    }

    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        throw FileSystemError(.unsupported, path)
    }

    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        fatalError("will never be supported")
    }

    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        fatalError("will never be supported")
    }
}


public struct GitRepositoryError: Error, CustomStringConvertible, DiagnosticLocationProviding {
    public let path: AbsolutePath
    public let message: String
    public let result: ProcessResult
    
    public struct Location: DiagnosticLocation {
        public let path: AbsolutePath
        public var description: String {
            return path.pathString
        }
    }

    public var diagnosticLocation: DiagnosticLocation? {
        return Location(path: path)
    }

    public var description: String {
        let stdout = (try? result.utf8Output()) ?? ""
        let stderr = (try? result.utf8stderrOutput()) ?? ""
        let output = (stdout + stderr).spm_chomp().spm_multilineIndent(count: 4)
        return "\(message):\n\(output)"
    }
}
