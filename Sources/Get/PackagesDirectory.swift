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

    /// Create a Package for a given repositories current state.
    //
    // FIXME: We *always* have a manifest, don't reparse it.
    private func createPackage(repo: Git.Repo) throws -> Package? {
        guard let origin = repo.origin else { throw Package.Error.noOrigin(repo.path.asString) }
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
