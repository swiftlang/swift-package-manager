/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

import func POSIX.getenv
import enum POSIX.Error
import class Foundation.ProcessInfo

enum GitRepositoryProviderError: Swift.Error {
    case gitCloneFailure(url: String, path: AbsolutePath)
}
extension GitRepositoryProviderError: CustomStringConvertible {
    var description: String {
        switch self {
        case .gitCloneFailure(let url, let path):
            return "Failed to clone \(url) to \(path)"
        }
    }
}

/// A `git` repository provider.
public class GitRepositoryProvider: RepositoryProvider {
    public init() {
    }
    
    public func fetch(repository: RepositorySpecifier, to path: AbsolutePath) throws {
        // Perform a bare clone.
        //
        // NOTE: We intentionally do not create a shallow clone here; the
        // expected cost of iterative updates on a full clone is less than on a
        // shallow clone.

        // FIXME: We need to define if this is only for the initial clone, or
        // also for the update, and if for the update then we need to handle it
        // here.

        // FIXME: Need to think about & handle submodules.
        precondition(!exists(path))
        
        do {
            // FIXME: We need infrastructure in this subsystem for reporting
            // status information.
            let env = ProcessInfo.processInfo.environment
            try system(
                Git.tool, "clone", "--bare", repository.url, path.asString,
                environment: env, message: "Cloning \(repository.url)")
        } catch POSIX.Error.exitStatus {
            // Git 2.0 or higher is required
            if let majorVersion = Git.majorVersionNumber, majorVersion < 2 {
                throw Utility.Error.obsoleteGitVersion
            } else {
                throw GitRepositoryProviderError.gitCloneFailure(url: repository.url, path: path)
            }
        }
    }

    public func open(repository: RepositorySpecifier, at path: AbsolutePath) -> Repository {
        return GitRepository(path: path)
    }

    public func cloneCheckout(
        repository: RepositorySpecifier,
        at sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) throws {
        // Clone using a shared object store with the canonical copy.
        //
        // We currently expect using shared storage here to be safe because we
        // only ever expect to attempt to use the working copy to materialize a
        // revision we selected in response to dependency resolution, and if we
        // re-resolve such that the objects in this repository changed, we would
        // only ever expect to get back a revision that remains present in the
        // object storage.
        //
        // NOTE: The above assumption may become violated once we have support
        // for editable packages, if we are also using this method to get that
        // copy. At that point we may need to expose control over this.
        //
        // FIXME: Need to think about & handle submodules.
        try Git.runCommandQuietly([
                Git.tool, "clone", "--shared", sourcePath.asString, destinationPath.asString])
    }

    public func openCheckout(at path: AbsolutePath) throws -> WorkingCheckout {
        return GitRepository(path: path)
    }
}

enum GitInterfaceError: Swift.Error {
    /// This indicates a problem communicating with the `git` tool.
    case malformedResponse(String)
}

/// A basic `git` repository.
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

    public init(path: AbsolutePath) {
        self.path = path
    }

    // MARK: Repository Interface

    public var tags: [String] { return tagsCache.getValue(self) }
    private var tagsCache = LazyCache(getTags)
    private func getTags() -> [String] {
        // FIXME: Error handling.
        let tagList = try! Git.runPopen([Git.tool, "-C", path.asString, "tag", "-l"])
        return tagList.characters.split(separator: "\n").map(String.init)
    }

    public func resolveRevision(tag: String) throws -> Revision {
        return try Revision(identifier: resolveHash(treeish: tag, type: "commit").bytes.asString!)
    }

    public func openFileView(revision: Revision) throws -> FileSystem {
        return try GitFileSystemView(repository: self, revision: revision)
    }

    // MARK: Working Checkout Interface

    public func getCurrentRevision() throws -> Revision {
        return Revision(identifier: try Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", "HEAD"]).chomp())
    }

    public func checkout(tag: String) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        try Git.runCommandQuietly([Git.tool, "-C", path.asString, "reset", "--hard", tag])
    }

    public func checkout(revision: Revision) throws {
        // FIXME: Audit behavior with off-branch tags in remote repositories, we
        // may need to take a little more care here.
        try Git.runCommandQuietly([Git.tool, "-C", path.asString, "reset", "--hard", revision.identifier])
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
        let response = try Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", specifier]).chomp()
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
        let treeInfo = try Git.runPopen([Git.tool, "-C", path.asString, "ls-tree", hash.bytes.asString!])

        var contents: [Tree.Entry] = []
        for line in treeInfo.components(separatedBy: "\n") {
            // Ignore empty lines.
            if line == "" { continue }
            
            // Each line in the response should match:
            //
            //   `mode type hash\tname`
            //
            // where `mode` is the 6-byte octal file mode, `type` is a 4-byte
            // type ("blob" or "tree"), `hash` is the hash, and the remainder of
            // the line is the file name.
            let bytes = ByteString(encodingAsUTF8: line)
            guard bytes.count > 6 + 1 + 4 + 1 + 40 + 1,
                  bytes.contents[6] == UInt8(ascii: " "),
                  bytes.contents[6 + 1 + 4] == UInt8(ascii: " "),
                  bytes.contents[6 + 1 + 4 + 1 + 40] == UInt8(ascii: "\t") else {
                throw GitInterfaceError.malformedResponse("unexpected tree entry '\(line)' in '\(treeInfo)'")
            }

            // Compute the mode.
            let mode = bytes.contents[0..<6].reduce(0) { (acc: Int, char: UInt8) in
                (acc << 3) | (Int(char) - Int(UInt8(ascii: "0")))
            }
            guard let type = Tree.Entry.EntryType(mode: mode),
                  let hash = Hash(asciiBytes: bytes.contents[(6 + 1 + 4 + 1)..<(6 + 1 + 4 + 1 + 40)]),
                  let name = ByteString(bytes.contents[(6 + 1 + 4 + 1 + 40 + 1)..<bytes.count]).asString else {
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
        // Get the contents using `cat-file`.
        //
        // FIXME: We need to get the raw bytes back, not a String.
        let output = try Git.runPopen([Git.tool, "-C", path.asString, "cat-file", "-p", hash.bytes.asString!])
        return ByteString(encodingAsUTF8: output)
    }
}

func ==(_ lhs: GitRepository.Commit, _ rhs: GitRepository.Commit) -> Bool {
    return lhs.hash == rhs.hash && lhs.tree == rhs.tree
}

func ==(_ lhs: GitRepository.Hash, _ rhs: GitRepository.Hash) -> Bool {
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
    
    func exists(_ path: AbsolutePath) -> Bool {
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
    
    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
        guard let entry = try getEntry(path) else {
            throw FileSystemError.noEntry
        }
        guard entry.type == .tree else {
            throw FileSystemError.notDirectory
        }

        return try getTree(entry.hash).contents.map{ $0.name }
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
}
