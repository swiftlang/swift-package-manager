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
import PackageType
import Utility

/**
 Implementation detail: a container for fetched packages.
 */
class PackagesDirectory {
    let prefix: String
    let manifestParser: (path: String, url: String) throws -> Manifest

    init(prefix: String, manifestParser: (path: String, url: String) throws -> Manifest) {
        self.prefix = prefix
        self.manifestParser = manifestParser
    }
}

extension PackagesDirectory: Fetcher {
    typealias T = Package

    func find(url: String) throws -> Fetchable? {
        for prefix in walk(self.prefix, recursively: false) {
            guard let repo = Git.Repo(path: prefix) else { continue }  //TODO warn user
            guard repo.origin == url else { continue }
            return try Package.make(repo, manifestParser: manifestParser)
        }
        return nil
    }

    func fetch(url: String) throws -> Fetchable {
        let dstdir = Path.join(prefix, Package.nameForURL(url))
        if let repo = Git.Repo(path: dstdir) where repo.origin == url {
            //TODO need to canonicalize the URL need URL struct
            return try RawClone(path: dstdir, manifestParser: manifestParser)
        }

        // fetch as well, clone does not fetch all tags, only tags on the master branch
        try Git.clone(url, to: dstdir).fetch()

        return try RawClone(path: dstdir, manifestParser: manifestParser)
    }

    func finalize(_ fetchable: Fetchable) throws -> Package {
        switch fetchable {
        case let clone as RawClone:
            let prefix = Path.join(self.prefix, clone.finalName)
            try mkdir(prefix.parentDirectory)
            try rename(clone.path, new: prefix)
            //TODO don't reparse the manifest!
            return try Package.make(Git.Repo(path: prefix)!, manifestParser: manifestParser)!
        case let pkg as Package:
            return pkg
        default:
            fatalError("Unexpected Fetchable Type: \(fetchable)")
        }
    }
}
