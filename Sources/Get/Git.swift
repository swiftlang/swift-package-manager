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
    class func clone(url: String, to dstdir: String) throws -> Repo {
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
            throw Error.GitCloneFailure(url, dstdir)
        }

        return Repo(path: dstdir)!  //TODO no bangs
    }
}

extension Git.Repo {
    var versions: [Version] {
        let out = (try? popen([Git.tool, "-C", path, "tag", "-l"])) ?? ""
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

    /**
     - Returns: true if the package versions in this repository
     are all prefixed with "v", otherwise false. If there are
     no versions, returns false.
     */
    var versionsArePrefixed: Bool {
        return (try? popen([Git.tool, "-C", path, "tag", "-l"]))?.hasPrefix("v") ?? false
    }
}
