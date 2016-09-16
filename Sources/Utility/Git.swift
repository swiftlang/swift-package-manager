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

extension Version {
    static func vprefix(_ string: String) -> Version? {
        if string.characters.first == "v" {
            return Version(string.characters.dropFirst())
        } else {
            return nil
        }
    }
}

public class Git {
    /// Compute the version -> tag mapping from a list of input `tags`.
    public static func convertTagsToVersionMap(_ tags: [String]) -> [Version: String] {
        // First, check if we need to restrict the tag set to version-specific tags.
        var knownVersions: [Version: String] = [:]
        for versionSpecificKey in Versioning.currentVersionSpecificKeys {
            for tag in tags where tag.hasSuffix(versionSpecificKey) {
                let specifier = String(tag.characters.dropLast(versionSpecificKey.characters.count))
                if let version = Version(specifier) ?? Version.vprefix(specifier) {
                    knownVersions[version] = tag
                }
            }

            // If we found tags at this version-specific key, we are done.
            if !knownVersions.isEmpty {
                return knownVersions
            }
        }
            
        // Otherwise, look for normal tags.
        for tag in tags {
            if let version = Version(tag) {
                knownVersions[version] = tag
            }
        }

        // If we didn't find any versions, look for 'v'-prefixed ones.
        //
        // FIXME: We should match both styles simultaneously.
        if knownVersions.isEmpty {
            for tag in tags {
                if let version = Version.vprefix(tag) {
                    knownVersions[version] = tag
                }
            }
        }
        return knownVersions
    }
    
    public class Repo {
        public let path: AbsolutePath

        public init?(path: AbsolutePath) {
            self.path = resolveSymlinks(path)
            guard isDirectory(path.appending(component: ".git")) else { return nil }
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

        /// The set of known versions and their tags.
        public lazy var knownVersions: [Version: String] = { repo in
            // Get the list of tags.
            let out = (try? Git.runPopen([Git.tool, "-C", repo.path.asString, "tag", "-l"])) ?? ""
            let tags = out.characters.split(separator: "\n").map{ String($0) }

            return Git.convertTagsToVersionMap(tags)
        }(self)

        /// The set of versions in the repository, in order.
        public lazy var versions: [Version] = { repo in
            return [Version](repo.knownVersions.keys).sorted()
        }(self)

        /// Check if repo contains a version tag
        public var hasVersion: Bool {
            return !versions.isEmpty
        }
        
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

        public func fetch() throws {
            try system(Git.tool, "-C", path.asString, "fetch", "--tags", "origin", environment: ProcessInfo.processInfo.environment, message: nil)
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

    /// Execute a git command while suppressing output.
    //
    // FIXME: Move clients of this to using real structured APIs.
    public class func runCommandQuietly(_ arguments: [String]) throws {
        try system(arguments)
    }

    /// Execute a git command and capture the output.
    //
    // FIXME: Move clients of this to using real structured APIs.
    public class func runPopen(_ arguments: [String]) throws -> String {
        return try popen(arguments)
    }
}
