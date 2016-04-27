/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 ---------------
 
 Iteratively update a package tree.
 
 A major issue currently is that this is all done in place and
 there is no undo.
 
 TODO report unreferenced dependencies
*/

import struct PackageDescription.Version
import struct PackageType.Manifest
import class PackageType.Package
import func POSIX.rename
import Utility
import Get

public func update(manifest rootManifest: Manifest, parser: (String, baseURL: String) throws -> Manifest, pkgdir: String, progress: (Status) -> Void) throws -> Delta
{
    //FIXME count is hardly a good metric
    progress(.Start(packageCount: walk(pkgdir, recursively: false).filter{ $0.isDirectory }.count))

    let pkgsdir = PackagesDirectory(root: pkgdir)
    let updater = Updater(dependencies: rootManifest.package.dependencies.map{ ($0.url, $0.versionRange) })
    var delta = Delta()

    while let ejecta = try updater.crank() {
        switch ejecta {
        case .Pending(let fetch):
            progress(.Fetching)
            let upgrade = try fetch()
            let result = try upgrade()

            switch result {
            case .NoChange(let url, let version):
                delta.unchanged.append((url, version))
            case .Changed(let url, let old, let new):
                precondition(old != new)
                delta.changed.append((url, old, new))
            }

        case .PleaseQueue(let url, let queue):
            let repo: Git.Repo
            if let å = pkgsdir.find(url: url) {
                repo = å
            } else {
                progress(.Cloning(url))
                let name = Package.name(url: url)
                let dstdir = Path.join(pkgsdir.root, "\(name)-0.0.0") //FIXME 0.0.0
                repo = try Git.clone(url, to: dstdir)
                delta.added.append(url)
            }

            let checkout = try Checkout(manifest: parser(repo.path, baseURL: repo.origin ?? "error"))

            try queue(checkout)

        case .Processed:
            break
        }
    }

    return delta
}

public enum Status {
    case Start(packageCount: Int)
    case Fetching
    case Cloning(String)
}
