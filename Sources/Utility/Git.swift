/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.realpath
import func POSIX.getenv
import libc

public class Git {
    public class Repo {
        public let path: String

        public init?(path: String) {
            guard let realroot = try? realpath(path) else { return nil }
            self.path = realroot
            guard Path.join(path, ".git").isDirectory else { return nil }
        }

        public lazy var origin: String? = { repo in
            do {
                guard let url = try Git.runPopen([Git.tool, "-C", repo.path, "config", "--get", "remote.origin.url"]).chuzzle() else {
                    return nil
                }
                if URL.scheme(url) == nil {
                    return try realpath(url)
                } else {
                    return url
                }

            } catch {
                //TODO better
                print("Bad git repository: \(repo.path)", to: &stderr)
                return nil
            }
        }(self)

        public var branch: String! {
            return try? Git.runPopen([Git.tool, "-C", path, "rev-parse", "--abbrev-ref", "HEAD"]).chomp()
        }

        public var sha: String! {
            return try? Git.runPopen([Git.tool, "-C", path, "rev-parse", "--verify", "HEAD"]).chomp()
        }
        
        public func versionSha(tag: String) throws -> String {
            return try Git.runPopen([Git.tool, "-C", path, "rev-parse", "--verify", "\(tag)"]).chomp()
        }
        
        public var hasLocalChanges: Bool {
            let changes = try? Git.runPopen([Git.tool, "-C", path, "status", "--porcelain"]).chomp()
            return !(changes?.isEmpty ?? true)
        }

        /**
         - Returns: true if the package versions in this repository
         are all prefixed with "v", otherwise false. If there are
         no versions, returns false.
         */
        public var versionsArePrefixed: Bool {
            return (try? Git.runPopen([Git.tool, "-C", path, "tag", "-l"]))?.hasPrefix("v") ?? false
        }

        public func fetch() throws {
            do {
                try system(Git.tool, "-C", path, "fetch", "--tags", "origin", environment: Git.environmentForClone, message: nil)
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

    @noreturn public class func checkGitVersion(_ error: ErrorProtocol) throws {
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

    /// Get the environment variables for proxys.
    public static var proxyVariableNames: [String] = [
      "http_proxy",
      "https_proxy",
    ]

    /// Get the environment to use when cloning.
    public static var environmentForClone: [String: String] = {
        // List of environment variables which might be useful while running a
        // git fetch.
        let environmentList = [
            "EDITOR",
            "GIT_ASKPASS",
            "LANG",
            "LANGUAGE",
            "PAGER",
            "SSH_ASKPASS",
            "SSH_AUTH_SOCK",
            "TERM",
            "XDG_CONFIG_HOME",
        ]
        var result = [String: String]()
        for name in environmentList + Git.proxyVariableNames {
            result[name] = getenv(name)
        }
        return result
    }()
}
