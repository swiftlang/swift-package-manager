/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

import struct PackageDescription.Version

/**
 Recursively fetches dependencies into "\(manifestPath)/../Packages"
 - Throws: Error.InvalidDependencyGraph
*/
public func get(_ manifest: Manifest, manifestParser: (path: AbsolutePath, url: String, version: Version?) throws -> Manifest) throws -> (rootPackage: Package, externalPackages: [Package]) {
    let extManifests = try fetchResolvedManifests(manifest, manifestParser: manifestParser)

    let rootPackage = Package(manifest: manifest)
    let extPackages = extManifests.map{ Package(manifest: $0) }

    let pkgs = extPackages + [rootPackage]
    
    for pkg in pkgs {
        pkg.dependencies = pkg.manifest.package.dependencies.map{ dep in pkgs.pick{ dep.url == $0.url }! }
    }
    
    return (rootPackage, extPackages)
}

private func fetchResolvedManifests(_ manifest: Manifest, manifestParser: (path: AbsolutePath, url: String, version: Version?) throws -> Manifest) throws -> [Manifest] {
    let dir = manifest.path.parentDirectory.appending("Packages")
    let box = PackagesDirectory(prefix: dir, manifestParser: manifestParser)

    //TODO don't lose the dependency information during the Fetcher process!

    let extManifests = try box.recursivelyFetch(manifest.dependencies)
    
    return extManifests
}

//TODO normalize urls eg http://github.com -> https://github.com
//TODO probably should respect any relocation that applies during git transfer
//TODO detect cycles?

extension Manifest {
    var dependencies: [(String, Range<Version>)] {
        return package.dependencies.map{ ($0.url, $0.versionRange) }
    }
}
