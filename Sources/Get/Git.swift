/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import func POSIX.realpath
import func POSIX.getenv
import enum POSIX.Error
import Utility

extension Git {
    public class func clone(_ url: String, to dstdir: String) throws -> Repo {
        // canonicalize URL
        var url = url
        if URL.scheme(url) == nil {
            url = try realpath(url)
        }

        do {
            //List of environment variables which might be useful while running git
            let environmentList = ["SSH_AUTH_SOCK", "GIT_ASKPASS", "SSH_ASKPASS", "XDG_CONFIG_HOME"
                , "LANG", "LANGUAGE", "EDITOR", "PAGER", "TERM"]
            let environment = environmentList.reduce([String:String]()) { (accum, env) in
                var newAccum = accum
                newAccum[env] = getenv(env)
                return newAccum
            }
            try system(Git.tool, "clone",
                       "--recursive",   // get submodules too so that developers can use these if they so choose
                "--depth", "10",
                url, dstdir, environment: environment, message: "Cloning \(url)")
        } catch POSIX.Error.ExitStatus {
            // Git 2.0 or higher is required
            if Git.majorVersionNumber < 2 {
                throw Utility.Error.ObsoleteGitVersion
            } else {
                throw Error.GitCloneFailure(url, dstdir)
            }
        }

        return Repo(path: dstdir)!  //TODO no bangs
    }
}

extension Git.Repo {
    public var versions: [Version] {
        let out = (try? Git.runPopen([Git.tool, "-C", path, "tag", "-l"])) ?? ""
        let tags = out.characters.split(separator: Character.newline)
        let versions = tags.flatMap(Version.init).sorted()
        if !versions.isEmpty {
            return versions
        } else {
            return tags.flatMap(Version.vprefix).sorted()
        }
    }

    /// Check if repo contains a version tag
    var hasVersion: Bool {
        return !versions.isEmpty
    }

    public func set(branch: Version, updateBranch: Bool = true) throws {
        let tag = (versionsArePrefixed ? "v" : "") + branch.description
        try Git.runPopen([Git.tool, "-C", path, "reset", "--hard", "refs/tags/\(tag)"])
        if updateBranch {
            try Git.runPopen([Git.tool, "-C", path, "branch", "-m", tag])
        }
    }
}
