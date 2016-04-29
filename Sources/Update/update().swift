/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 -----------------------------------------------------------------
 
 Iteratively update a package tree.

 TODO read the manifest without modifying the checkout
 TODO report unreferenced dependencies
 TODO recognize cyclic dependencies
 TODO use this code for most of `get()` also
 TODO recover when a graph restriction changes the version of an already parsed manifest
*/

import struct PackageDescription.Version
import struct PackageType.Manifest
import class PackageType.Package
import func POSIX.rename
import Utility
import Get

public func update(dependencies: [(String, Range<Version>)], manifestParser: (String, baseURL: String) throws -> Manifest, pkgdir: String, progress: (Status) -> Void) throws -> Delta
{
    let pkgsdir = PackagesDirectory(root: pkgdir)
    let updater = Updater(dependencies: dependencies)
    var delta = Delta()

    progress(.Start(packageCount: pkgsdir.count))

    while let turn = try updater.crank() {
        switch turn {
        case .Fetch(let url):
            if let repo = pkgsdir.find(url: url) {
                progress(.Fetching(url))
                try repo.fetch(quick: true)
            } else {
                progress(.Cloning(url))

                let name = Package.name(url: url)
                let dstdir = Path.join(pkgsdir.root, "\(name)-0.0.0") //FIXME 0.0.0
                try Git.clone(url, to: dstdir)

                delta.added.append(url)
            }

        case .ReadManifest(let job):
            try job { url, versionRange in
                guard let repo = pkgsdir.find(url: url) else { fatalError() }  //FIXME make generic, pass repo to Updater to pass back
                let newVersion: Version! = repo ~= versionRange
                progress(.Parsing(url, newVersion))

                if newVersion != repo.version {
                    // checks out only Package.swift for the selected version
                    // FIXME checkout somewhere else!
                    var vstr = "\(newVersion)"
                    if repo.versionsArePrefixed { vstr = "v\(vstr)" }
                    try system(Git.tool, "-C", repo.path, "checkout", "refs/tags/\(vstr)", "--", "Package.swift")
                }

                let manifest = try manifestParser(repo.path, baseURL: url)

                if newVersion != repo.version {
                    try system(Git.tool, "-C", repo.path, "checkout", "Package.swift")
                }

                let specs = manifest.package.dependencies.map{ (url: $0.url, versionRange: $0.versionRange) }

                return (specs, newVersion)
            }

        case .Update(let url, let versionRange):
            guard let repo = pkgsdir.find(url: url) else { fatalError() } //FIXME associate repo object or something
            let oldVersion = repo.version

            // ⬇⬇ FIXME
            let newVersion: Version! = repo ~= versionRange
            guard newVersion != oldVersion else { continue }
            progress(.Updating(url, newVersion))
            // ⬆⬆ FIXME


            let newpath = Path.join(repo.path, "../\(repo.name)-\(newVersion)").normpath
            try repo.set(branch: newVersion)
            try rename(old: repo.path, new: newpath)

            delta.changed.append((url, old: oldVersion, new: newVersion))
        }
    }

    return delta
}

public enum Status {
    case Start(packageCount: Int)
    case Fetching(URL)
    case Cloning(URL)
    case Parsing(URL, Version)
    case Updating(URL, Version)
}
