/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import POSIX
import sys

class Git {
    class Repo {
        let root: String

        init?(root: String) {
            guard let realroot = try? realpath(root) else { self.root = ""; return nil }
            self.root = realroot
            guard Path.join(root, ".git").isDirectory else { return nil }
        }

        lazy var origin: String? = { repo in
            do {
                return try popen([Git.tool, "-C", repo.root, "config", "--get", "remote.origin.url"]).chuzzle()
            } catch {
                //TODO better
                print("Bad git repository: \(repo.root)")
                return ""
            }
        }(self)

        var versions: [Version] {
            //TODO separator is probably \r\n on Windows
            let out = (try? popen([Git.tool, "-C", root, "tag", "-l"])) ?? ""
            let tags = out.characters.split("\n")
            let versions = tags.flatMap(Version.init).sort()
            if !versions.isEmpty {
                return versions
            } else {
                return tags.flatMap(Version.vprefix).sort()
            }
        }

        var branch: String! {
            return try? popen([Git.tool, "-C", root, "rev-parse", "--abbrev-ref", "HEAD"]).chomp()
        }
    }

    class func clone(url: String, to dstdir: PathString) throws -> Repo {
        try system(Git.tool, "clone",
            "--recursive",          // get submodules too so that developers can use these if they so choose
            "--depth", "10",
            url, dstdir)
        return Repo(root: dstdir)!  //TODO no bangs
    }

    class var tool: String {
        return getenv("SWIFT_GIT") ?? "git"
    }
}



extension Version {
    private static func vprefix(string: String.CharacterView) -> Version? {
        if string.first == "v" {
            return Version(string.dropFirst())
        } else {
            return nil
        }
    }
}
