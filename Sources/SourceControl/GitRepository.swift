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
            bytes = ByteString(encodingAsUTF8: identifier)
            if bytes.count != 40 {
                return nil
            }
            for byte in bytes.contents {
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"),
                     UInt8(ascii: "a")...UInt8(ascii: "z"):
                    continue
                default:
                    return nil
                }
            }
        }
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
        return try Revision(identifier: resolveHash(treeish: tag).bytes.asString!)
    }

    // MARK: Git Operations

    func resolveHash(treeish: String) throws -> Hash {
        let response = try Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", treeish]).chomp()
        if let hash = Hash(response) {
            return hash
        } else {
            throw GitInterfaceError.malformedResponse("expected an object hash in \(response)")
        }
    }
}

func ==(_ lhs: GitRepository.Hash, _ rhs: GitRepository.Hash) -> Bool {
    return lhs.bytes == rhs.bytes
}
