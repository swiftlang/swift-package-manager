/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import class Utility.Git

extension Git.Repo {
    var version: Version {
        var branch = self.branch
        if branch.hasPrefix("heads/") {
            branch = String(branch.characters.dropFirst(6))
        }
        if branch.hasPrefix("v") {
            branch = String(branch.characters.dropFirst())
        }
        return Version(branch)!
    }

    var name: String {
        //FIXME lame
        return String(path.basename.characters.dropLast(version.description.characters.count + 1))
    }
}

func ~=(repo: Git.Repo, vv: Range<Version>) -> Version? {
    return repo.versions.filter{ $0.isStable && vv ~= $0 }.sorted().last
}
