/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import PackageType
import Utility

extension Package {
    // FIXME we *always* have a manifest, don't reparse it

    static func make(repo: Git.Repo, manifestParser: (path: String, url: String) throws -> Manifest) throws -> Package {
        let path = repo.path
        guard let origin = repo.origin else { throw Error.NoOrigin(path) }
        let manifest = try manifestParser(path: path, url: origin)
        let name = Package.name(manifest: manifest, url: origin)
        let versionString = path.basename.characters.dropFirst(name.characters.count + 1)
        guard let version = Version(versionString) else { throw Package.Error.NoVersion(path) }
        return Package(manifest: manifest, url: origin, version: version)
    }
}

extension Package: Fetchable {
    var children: [(String, Range<Version>)] {
        return manifest.package.dependencies.map{ ($0.url, $0.versionRange) }
    }

    private var versionString: String.CharacterView {
        return path.basename.characters.dropFirst(name.characters.count + 1)
    }

    var version: Version {
        return Version(versionString)!
    }

    func constrain(to versionRange: Range<Version>) -> Version? {
        return nil
    }

    var availableVersions: [Version] {
        return [version]
    }

    func setVersion(_ newValue: Version) throws {
        throw Get.Error.InvalidDependencyGraph(url)
    }
}
