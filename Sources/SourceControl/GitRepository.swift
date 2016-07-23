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
        precondition(!exists(path))
        
        do {
            // FIXME: We need infrastructure in this subsystem for reporting
            // status information.
          #if os(Linux)
            let env = ProcessInfo.processInfo().environment
          #else
            let env = ProcessInfo.processInfo.environment
          #endif
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
        // FIXME: Cache this.
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
// repositories. This may prove inconvenient what is currently `Repository`
// becomes inconvenient or incompatible with the ideal interface for this
// class. It is possible we should rename `Repository` to something more
// abstract, and change the provider to just return an adaptor around this
// class.
public class GitRepository: Repository {
    /// A hash object.
    struct Hash: Equatable {
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
    let path: AbsolutePath

    init(path: AbsolutePath) {
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

    /// Load the commit referenced by `hash`.
    func read(commit hash: Hash) throws -> Commit {
        // Currently, we just load the tree, using the typed `rev-parse` syntax.
        let treeHash = try resolveHash(treeish: hash.bytes.asString!, type: "tree")

        return Commit(hash: hash, tree: treeHash)
    }

    /// Load a tree object.
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
}

func ==(_ lhs: GitRepository.Commit, _ rhs: GitRepository.Commit) -> Bool {
    return lhs.hash == rhs.hash && lhs.tree == rhs.tree
}

func ==(_ lhs: GitRepository.Hash, _ rhs: GitRepository.Hash) -> Bool {
    return lhs.bytes == rhs.bytes
}
import libc
