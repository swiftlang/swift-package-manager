/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import struct PackageDescription.Version
import PackageModel
import Utility

extension Package {
    // FIXME we *always* have a manifest, don't reparse it

    static func make(repo: Git.Repo, manifestParser: (path: AbsolutePath, url: String) throws -> Manifest) throws -> Package? {
        guard let origin = repo.origin else { throw Error.noOrigin(repo.path.asString) }
        let manifest = try manifestParser(path: repo.path, url: origin)

        // Compute the package version.
        //
        // FIXME: This is really gross, and should not be necessary.
        let packagePath = manifest.path.parentDirectory
        let packageName = manifest.package.name ?? Package.nameForURL(origin)
        let packageVersionString = packagePath.basename.characters.dropFirst(packageName.characters.count + 1)
        guard let version = Version(packageVersionString) else {
            return nil
        }
        
        return Package(manifest: manifest, url: origin, version: version)
    }
}

extension Package: Fetchable {
    var children: [(String, Range<Version>)] {
        return manifest.package.dependencies.map{ ($0.url, $0.versionRange) }
    }

    var currentVersion: Version {
        return self.version!
    }

    func constrain(to versionRange: Range<Version>) -> Version? {
        return nil
    }

    var availableVersions: [Version] {
        return [currentVersion]
    }

    func setCurrentVersion(_ newValue: Version) throws {
        throw Get.Error.invalidDependencyGraph(url)
    }
}
