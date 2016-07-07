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
import class Foundation.NSProcessInfo
import Utility

extension Git {
    class func clone(_ url: String, to dstdir: String) throws -> Repo {
        // canonicalize URL
        var url = url
        if URL.scheme(url) == nil {
            url = try realpath(url)
        }

        do {
          #if os(Linux)
            let env = NSProcessInfo.processInfo().environment
          #else
            let env = NSProcessInfo.processInfo.environment
          #endif
            try system(Git.tool, "clone",
                       "--recursive",   // get submodules too so that developers can use these if they so choose
                "--depth", "10",
                url, dstdir, environment: env, message: "Cloning \(url)")
        } catch POSIX.Error.exitStatus {
            // Git 2.0 or higher is required
            if Git.majorVersionNumber < 2 {
                throw Utility.Error.obsoleteGitVersion
            } else {
                throw Error.gitCloneFailure(url, dstdir)
            }
        }

        return Repo(path: dstdir)!  //TODO no bangs
    }
}

extension Git.Repo {
    var versions: [Version] {
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
}
