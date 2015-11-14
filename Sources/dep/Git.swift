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

    class func clone(url: String, to dstdir: String) throws -> Repo {
        let args = [Git.tool, "clone",
            "--recursive",          // get submodules too so that developers can use these if they so choose
            "--depth", "10",
            url, dstdir]

        if sys.verbosity == .Concise {
            var out = ""
            do {
                print("Cloning", Path(dstdir).relative(to: "."), terminator: "")
                defer{ print("") }
                try popen(args, redirectStandardError: true) { line in
                    out += line
                    for _ in out.characters.split("\n") {
                        print(".", terminator: "")
                    }
                }
            } catch ShellError.popen(let foo) {
                print("$", prettyArguments(args), toStream: &stderr)
                print(out, toStream: &stderr)
                throw ShellError.popen(foo)
            }
        } else {
            try system(args)
        }

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
