/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.VersionRange
import struct PackageDescription.Version
import PackageType
import Utility
import libc

/**
 Initially we clone into a non-final form because we may need to
 adjust the dependency graph due to further specifications as
 we clone more repositories. This is the non-final form. Once
 `recursivelyFetch` completes we finalize these clones into our
 Sandbox.
 */
class RawClone: Fetchable {
    let path: String
    let manifestParser: (path: String, url: String) throws -> Manifest

    // lazy because the tip of the default branch does not have to be a valid package
    //FIXME we should error gracefully if a selected version does not however
    var manifest: Manifest! {
        if let manifest = _manifest {
            return manifest
        } else {
            _manifest = try? manifestParser(path: path, url: repo.origin!)
            return _manifest
        }
    }
    private var _manifest: Manifest?

    init(path: String, manifestParser: (path: String, url: String) throws -> Manifest) throws {
        self.path = path
        self.manifestParser = manifestParser
        if !repo.hasVersion {
            throw Error.Unversioned(path)
        }
    }

    var repo: Git.Repo {
        return Git.Repo(path: path)!
    }

    var version: Version {
        var branch = repo.branch
        if branch.hasPrefix("heads/") {
            branch = String(branch.characters.dropFirst(6))
        }
        if branch.hasPrefix("v") {
            branch = String(branch.characters.dropFirst())
        }
        return Version(branch)!
    }

    /// contract, you cannot call this before you have attempted to `constrain` this clone
    func setVersion(ver: Version) throws {
        let packageVersionsArePrefixed = repo.versionsArePrefixed
        let v = (packageVersionsArePrefixed ? "v" : "") + ver.description
        try Git.runPopen([Git.tool, "-C", path, "reset", "--hard", v])
        try Git.runPopen([Git.tool, "-C", path, "branch", "-m", v])

        print("Resolved version:", ver)

        // we must re-read the manifest
        _manifest = nil
        if manifest == nil {
            throw Error.NoManifest(path, ver)
        }
    }

    func constrain(to versionRange: VersionRange) -> Version? {
        guard !versionRange.singleVersion else {
            return availableVersions.contains(versionRange.start) ? versionRange.start : nil
        } 
        
        let versionRange = versionRange.range
        return availableVersions.filter {
            // not using `contains` as it uses successor() and for Range<Version>
            // this involves iterating from 0 to Int.max!
            versionRange ~= $0
        }.last
    }

    var children: [(String, VersionRange)] {
        guard manifest != nil else {
            // manifest may not exist, if so the package is BAD,
            // still: we should not crash. Build failure will occur
            // shortly after this because we cannot `setVersion`
            return []
        }

        //COPY PASTA from Package.dependencies
        return manifest.dependencies
    }

    var url: String {
        return repo.origin ?? "BAD_ORIGIN"
    }

    var availableVersions: [Version] {
        return repo.versions
    }

    var finalName: String {
        let name = manifest.package.name ?? Package.nameForURL(url)
        return "\(name)-\(version)"
    }
}
