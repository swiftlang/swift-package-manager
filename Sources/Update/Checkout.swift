import struct PackageDescription.Version
import PackageType
import Utility
import Get

struct Checkout: Equatable, Hashable {
    var path: String {
        return manifest.path.parentDirectory
    }

    private let manifest: Manifest
    let repo: Git.Repo
    let url: String

    var deps: [(String, Range<Version>)] {
        return manifest.package.dependencies.map{ ($0.url, $0.versionRange) }
    }

    var name: String {
        return Package.name(manifest: manifest, url: url)
    }

    var version: Version {
        return Version(path.basename.characters.dropFirst(name.characters.count + 1))!
    }

    init(manifest: Manifest) throws {
        guard let repo = Git.Repo(path: manifest.path.parentDirectory) else { fatalError() }
        self.repo = repo
        guard let origin = repo.origin else { fatalError() }
        self.url = origin
        self.manifest = manifest
    }

    var hashValue: Int {
        return url.hashValue
    }
}

func ==(lhs: Checkout, rhs: Checkout) -> Bool {
    return lhs.url == rhs.url
}

