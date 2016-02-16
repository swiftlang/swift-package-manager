/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.realpath
import func POSIX.getenv

public class Git {
    public class Repo {
        public let root: String  //TODO rename path

        public init?(root: String) {
            guard let realroot = try? realpath(root) else { return nil }
            self.root = realroot
            guard Path.join(root, ".git").isDirectory else { return nil }
        }

        public lazy var origin: String? = { repo in
            do {
                guard let url = try popen([Git.tool, "-C", repo.root, "config", "--get", "remote.origin.url"]).chuzzle() else {
                    return nil
                }
                if URL.scheme(url) == nil {
                    return try realpath(url)
                } else {
                    return url
                }

            } catch {
                //TODO better
                print("Bad git repository: \(repo.root)", toStream: &stderr)
                return nil
            }
        }(self)

        public var branch: String! {
            return try? popen([Git.tool, "-C", root, "rev-parse", "--abbrev-ref", "HEAD"]).chomp()
        }

        public func fetch() throws {
            try system(Git.tool, "-C", root, "fetch", "--tags", "origin", message: nil)
        }
    }

    public class var tool: String {
        return getenv("SWIFT_GIT") ?? "git"
    }
}
