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

/// A basic `git` repository.
private class GitRepository: Repository {
    /// The path of the repository on disk.
    let path: AbsolutePath

    init(path: AbsolutePath) {
        self.path = path
    }
    
    var tags: [String] { return tagsCache.getValue(self) }
    var tagsCache = LazyCache(getTags)
    func getTags() -> [String] {
        // FIXME: Error handling.
        let tagList = try! Git.runPopen([Git.tool, "-C", path.asString, "tag", "-l"])
        return tagList.characters.split(separator: "\n").map(String.init)
    }

    func resolveRevision(tag: String) throws -> Revision {
        let hash = try Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", tag]).chomp()
        // FIXME: We should validate we got a hash.
        return Revision(identifier: hash)
    }
}
