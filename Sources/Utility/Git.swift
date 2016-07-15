/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import func POSIX.realpath
import func POSIX.getenv
import libc
import class Foundation.ProcessInfo

public class Git {
    public class Repo {
        public let path: AbsolutePath

        public init?(path: AbsolutePath) {
            self.path = resolveSymlinks(path)
            guard path.appending(".git").asString.isDirectory else { return nil }
        }

        public lazy var origin: String? = { repo in
            do {
                guard let url = try Git.runPopen([Git.tool, "-C", repo.path.asString, "config", "--get", "remote.origin.url"]).chuzzle() else {
                    return nil
                }
                if URL.scheme(url) == nil {
                    return try realpath(url)
                } else {
                    return url
                }

            } catch {
                //TODO better
                print("Bad git repository: \(repo.path.asString)", to: &stderr)
                return nil
            }
        }(self)

        public var branch: String! {
            return try? Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--abbrev-ref", "HEAD"]).chomp()
        }

        public var sha: String! {
            return try? Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", "HEAD"]).chomp()
        }
        public func versionSha(tag: String) throws -> String {
            return try Git.runPopen([Git.tool, "-C", path.asString, "rev-parse", "--verify", "\(tag)"]).chomp()
        }
        public var hasLocalChanges: Bool {
            let changes = try? Git.runPopen([Git.tool, "-C", path.asString, "status", "--porcelain"]).chomp()
            return !(changes?.isEmpty ?? true)
        }

        /**
         - Returns: true if the package versions in this repository
         are all prefixed with "v", otherwise false. If there are
         no versions, returns false.
         */
        public var versionsArePrefixed: Bool {
            return (try? Git.runPopen([Git.tool, "-C", path.asString, "tag", "-l"]))?.hasPrefix("v") ?? false
        }

        public func fetch() throws {
            do {
              #if os(Linux)
                try system(Git.tool, "-C", path.asString, "fetch", "--tags", "origin", environment: ProcessInfo.processInfo().environment, message: nil)
              #else
                try system(Git.tool, "-C", path.asString, "fetch", "--tags", "origin", environment: ProcessInfo.processInfo.environment, message: nil)
              #endif
            } catch let errror {
                try Git.checkGitVersion(errror)
            }
        }
    }

    public class var tool: String {
        return getenv("SWIFT_GIT") ?? "git"
    }

    public class var version: String! {
        return try? Git.runPopen([Git.tool, "version"])
    }

    public class var majorVersionNumber: Int? {
        let prefix = "git version"
        var version = self.version!
        if version.hasPrefix(prefix) {
            let prefixRange = version.startIndex...version.index(version.startIndex, offsetBy: prefix.characters.count)
            version.removeSubrange(prefixRange)
        }
        guard let first = version.characters.first else {
            return nil
        }
        return Int(String(first))
    }

    @noreturn public class func checkGitVersion(_ error: Swift.Error) throws {
        // Git 2.0 or higher is required
        if Git.majorVersionNumber < 2 {
            // FIXME: This does not belong here.
            print("error: ", Error.obsoleteGitVersion)
            exit(1)
        } else {
            throw error
        }
    }

    /// Execute a git command while suppressing output.
    //
    // FIXME: Move clients of this to using real structured APIs.
    public class func runCommandQuietly(_ arguments: [String]) throws {
        do {
            try system(arguments)
        } catch let error  {
            try checkGitVersion(error)
        }
    }

    /// Execute a git command and capture the output.
    //
    // FIXME: Move clients of this to using real structured APIs.
    public class func runPopen(_ arguments: [String]) throws -> String {
        do {
            return try popen(arguments)
        } catch let error  {
            try checkGitVersion(error)
        }
    }
}
