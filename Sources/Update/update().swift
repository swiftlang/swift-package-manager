/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import func libc.fflush
import var libc.stdout
import Utility
import POSIX
import Get

public enum Error: ErrorProtocol {
    case NoRepo(String)
    case NoVersion(String)
    case NoPackageName(String)
}

public enum Status {
    case Start(packageCount: Int)
    case Fetching(String)
}

public func update(root: String, progress: (Status) -> Void) throws -> Delta {
    let dirs = walk(root, recursively: false).filter{ $0.isDirectory }

    progress(.Start(packageCount: dirs.count))

    let updates = try dirs.map { clonepath throws -> (String, Version, Version) in
        progress(.Fetching(clonepath))
        return try update(package: clonepath)
    }

    return updates.reduce(Delta()) { delta, update in
        var delta = delta
        let (name, old, new) = update
        if new == old {
            delta.unchanged.append((name, old))
        } else if new > old {
            delta.upgraded.append((name, old, new))
        } else if old > new {
            delta.downgraded.append((name, old, new))
        }
        return delta
    }
}

extension Git.Repo {
    func upgrade() throws -> Version {
        guard let latestVersion = versions.last else { throw Error.NoVersion(path) }
        let vstr = (versionsArePrefixed ? "v" : "") + latestVersion.description
        let name = try pkgname()
        try Git.runPopen([Git.tool, "-C", path, "reset", "--hard", "refs/tags/\(vstr)"])
        try Git.runPopen([Git.tool, "-C", path, "branch", "-m", vstr])
        try rename(old: path, new: "\(name)-\(vstr)")
        return latestVersion
    }

    /**
     TODO should be at a higher module level.
     FIXME DRY
     FIXME also this is gross and flakier than necessary.
    */
    func pkgname() throws -> String {
        let version = self.version.description.characters
        let rawname = path.basename.characters.dropLast(version.count + 1)
        guard let pkgname = String(rawname).chuzzle() where !pkgname.isEmpty else { throw Error.NoPackageName(path) }
        return pkgname
    }

    var version: Version {
        var branch = self.branch.characters
        if branch.starts(with: "heads/".characters) {
            branch = branch.dropFirst(6)
        }
        guard let version = Version(branch) else { fatalError() }
        return version
    }
}

private func update(package path: String) throws -> (String, Version, Version) {
    guard let repo = Git.Repo(path: path) else { throw Error.NoRepo(path) }

    let oldVersion = repo.version

    try repo.fetch()
    let newVersion = try repo.upgrade()

    return (try repo.pkgname(), oldVersion, newVersion)
}
