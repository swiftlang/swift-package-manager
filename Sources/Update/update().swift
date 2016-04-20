/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import Utility
import POSIX
import Get

enum Error: ErrorProtocol {
    case NoRepo(String)
    case NoVersion(String)
    case NoPackageName(String)
}

public struct Delta<T> {
    public var added: [T] = []
    public var removed: [T] = []
    public var upgraded: [T] = []
    public var downgraded: [T] = []
}

public func update(root: String) throws {
    for path in walk(root, recursively: false) {
        guard path.isDirectory else { continue }
        guard let repo = Git.Repo(path: path) else { throw Error.NoRepo(path) }
        let oldVersion = repo.version
        try repo.fetch()
        try repo.upgrade()
        print("updated:", try repo.pkgname(), oldVersion, "->", repo.version)
    }
}

extension Git.Repo {
    func upgrade() throws {
        guard let latestVersion = versions.last else { throw Error.NoVersion(path) }
        let vstr = (versionsArePrefixed ? "v" : "") + latestVersion.description
        let name = try pkgname()
        try Git.runPopen([Git.tool, "-C", path, "reset", "--hard", "refs/tags/\(vstr)"])
        try Git.runPopen([Git.tool, "-C", path, "branch", "-m", vstr])
        try rename(old: path, new: "\(name)-\(vstr)")
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
