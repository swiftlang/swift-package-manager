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
import func POSIX.rename

/**
 Implementation detail: a container for fetched packages.
 */
class PackagesDirectory {
    let prefix: AbsolutePath
    let manifestParser: (path: AbsolutePath, url: String) throws -> Manifest

    init(prefix: AbsolutePath, manifestParser: (path: AbsolutePath, url: String) throws -> Manifest) {
        self.prefix = prefix
        self.manifestParser = manifestParser
    }
    
    /// The set of all repositories available within the `Packages` directory, by origin.
    fileprivate lazy var availableRepositories: [String: Git.Repo] = { [unowned self] in
        // FIXME: Lift this higher.
        guard localFileSystem.isDirectory(self.prefix) else { return [:] }

        var result = Dictionary<String, Git.Repo>()
        for name in try! localFileSystem.getDirectoryContents(self.prefix) {
            let prefix = self.prefix.appending(RelativePath(name))
            guard let repo = Git.Repo(path: prefix), let origin = repo.origin else { continue } // TODO: Warn user.
            result[origin] = repo
        }
        return result
    }()
}

extension PackagesDirectory: Fetcher {
    typealias T = Package

    /// Extract the package version from a path.
    //
    // FIXME: This is really gross, and should not be necessary -- we should
    // maintain the state we care about in a well defined format, not just via
    // the file system path.
    private func extractPackageVersion(_ name: String) -> Version? {
        // Search each suffix separated by a '-'.
        var name = name
        while let separatorIndex = name.characters.rindex(of: "-") {
            // See if there is a parseable version (there could be prerelease identifiers, etc.).
            let versionString = String(name.characters.suffix(from: name.index(after: separatorIndex)))
            if let version = Version(versionString) {
                return version
            }

            // If not, keep looking.
            name = String(name.characters.prefix(upTo: separatorIndex))
        }
        return nil
    }
        
    /// Create a Package for a given repositories current state.
    //
    // FIXME: We *always* have a manifest, don't reparse it.
    private func createPackage(repo: Git.Repo) throws -> Package? {
        guard let origin = repo.origin else {
            throw Package.Error.noOrigin(repo.path.asString)
        }
        guard let version = extractPackageVersion(repo.path.basename) else {
            return nil
        }
        
        let manifest = try manifestParser(path: repo.path, url: origin)
        return Package(manifest: manifest, url: origin, version: version)
    }
    
    func find(url: String) throws -> Fetchable? {
        if let repo = availableRepositories[url] {
            return try createPackage(repo: repo)
        }
        return nil
    }

    func fetch(url: String) throws -> Fetchable {
        let dstdir = prefix.appending(RelativePath(Package.nameForURL(url)))
        if let repo = Git.Repo(path: dstdir), repo.origin == url {
            //TODO need to canonicalize the URL need URL struct
            return try RawClone(path: dstdir, manifestParser: manifestParser)
        }

        // fetch as well, clone does not fetch all tags, only tags on the master branch
        try Git.clone(url, to: dstdir).fetch()

        return try RawClone(path: dstdir, manifestParser: manifestParser)
    }

    func finalize(_ fetchable: Fetchable) throws -> Package {
        switch fetchable {
        case let clone as RawClone:
            let prefix = self.prefix.appending(RelativePath(clone.finalName))
            try Utility.makeDirectories(prefix.parentDirectory.asString)
            try rename(old: clone.path.asString, new: prefix.asString)
            //TODO don't reparse the manifest!
            let repo = Git.Repo(path: prefix)!

            // Update the available repositories.
            availableRepositories[repo.origin!] = repo
            
            return try createPackage(repo: repo)!
        case let pkg as Package:
            return pkg
        default:
            fatalError("Unexpected Fetchable Type: \(fetchable)")
        }
    }
}
