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

enum GitRepositoryProviderError: ErrorProtocol {
    case gitCloneFailure(url: String, path: String)
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
    
    public func fetch(repository: RepositorySpecifier, to path: String) throws {
        // Perform a bare clone.
        //
        // NOTE: We intentionally do not create a shallow clone here; the
        // expected cost of iterative updates on a full clone is less than on a
        // shallow clone.

        // FIXME: We need to define if this is only for the initial clone, or
        // also for the update, and if for the update then we need to handle it
        // here.
        precondition(!path.exists)
        
        do {
            // FIXME: We need infrastructure in this subsystem for reporting
            // status information.
            try system(
                Git.tool, "clone", "--bare", repository.url, path,
                environment: ProcessInfo.processInfo().environment, message: "Cloning \(repository.url)")
        } catch POSIX.Error.exitStatus {
            // Git 2.0 or higher is required
            if Git.majorVersionNumber < 2 {
                throw Utility.Error.obsoleteGitVersion
            } else {
                throw GitRepositoryProviderError.gitCloneFailure(url: repository.url, path: path)
            }
        }
    }

    public func open(repository: RepositorySpecifier, at path: String) -> Repository {
        // FIXME: Cache this.
        return GitRepository(path: path)
    }
}

/// A basic `git` repository.
private class GitRepository: Repository {
    /// The path of the repository on disk.
    let path: String

    init(path: String) {
        self.path = path
    }
    
    var tags: [String] { return tagsCache.getValue(self) }
    var tagsCache = LazyCache(getTags)
    func getTags() -> [String] {
        // FIXME: Error handling.
        let tagList = try! Git.runPopen([Git.tool, "-C", path, "tag", "-l"]) ?? ""
        return tagList.characters.split(separator: Character.newline).map(String.init)
    }
}
