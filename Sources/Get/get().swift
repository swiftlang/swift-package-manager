/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class PackageType.Package
import PackageType
import Utility

/**
 Recursively fetches dependencies into "\(manifestPath)/../Packages"
 - Throws: Error.InvalidDependencyGraph
 - Returns: The modules that this manifest requires building
*/
public func get(manifest: Manifest, manifestParser: (path: String, url: String) throws -> Manifest) throws -> [Package] {
    let dir = Path.join(manifest.path.parentDirectory, "Packages")
    let box = PackagesDirectory(prefix: dir, manifestParser: manifestParser)

    //TODO don't lose the dependency information during the Fetcher process!

    let pkgs = try box.recursivelyFetch(manifest.dependencies) + [Package(manifest: manifest, url: manifest.path.parentDirectory)]
    for pkg in pkgs {
        pkg.dependencies = pkg.manifest.package.dependencies.map{ dep in pkgs.pick{ dep.url == $0.url }! }
    }
    return pkgs
}

//TODO normalize urls eg http://github.com -> https://github.com
//TODO probably should respect any relocation that applies during git transfer
//TODO detect cycles?


import PackageDescription

extension Manifest {
    var dependencies: [(String, Range<Version>)] {
        return package.dependencies.map{ ($0.url, $0.versionRange) }
    }
}
