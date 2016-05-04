/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import class PackageDescription.Package
import PackageType
import Utility
import Get

struct PackagesDirectory {
    let root: String

    func find(url: String) -> Git.Repo? {
        for dir in walk(root, recursively: false) {
            guard let repo = Git.Repo(path: dir) else { continue }
            if repo.origin == url { return repo }
        }
        return nil
    }

    var count: Int {
        return walk(root, recursively: false).filter{ $0.isDirectory }.count
    }
}
