/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import func POSIX.mkdir
import func POSIX.rename
import ManifestParser
import PackageType
import Utility

/**
 Implementation detail: a container for fetched packages.
 */
class PackagesDirectory {
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }
}

extension PackagesDirectory: Fetcher {
    typealias T = Package

    func find(url url: String) throws -> Fetchable? {
        for prefix in walk(self.prefix, recursively: false) {
            guard let repo = Git.Repo(root: prefix) else { continue }  //TODO warn user
            guard repo.origin == url else { continue }
            return try Package.make(repo: repo)
        }
        return nil
    }

    func fetch(url url: String) throws -> Fetchable {
        let dstdir = Path.join(prefix, Package.nameForURL(url))
        if let repo = Git.Repo(root: dstdir) where repo.origin == url {
            //TODO need to canonicalize the URL need URL struct
            return try RawClone(path: dstdir)
        }

        // fetch as well, clone does not fetch all tags, only tags on the master branch
        try Git.clone(url, to: dstdir).fetch()

        return try RawClone(path: dstdir)
    }

    func finalize(fetchable: Fetchable) throws -> Package {
        switch fetchable {
        case let clone as RawClone:
            let prefix = Path.join(self.prefix, clone.finalName)
            try mkdir(prefix.parentDirectory)
            try rename(old: clone.path, new: prefix)
            return try Package.make(repo: Git.Repo(root: prefix)!)!
        case let pkg as Package:
            return pkg
        default:
            fatalError("Unexpected Fetchable Type: \(fetchable)")
        }
    }
}
