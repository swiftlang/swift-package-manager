/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class PackageDescription.Package
import struct PackageDescription.Version
import POSIX
import sys


/**
 Recursively fetches dependencies into this Sandbox.
 - Throws: Error.InvalidDependencyGraph
 - Returns: An array of (downloaded) Packages, ordered ready for building.
*/
public func get(specs: [PackageDescription.Package.Dependency], prefix: String) throws -> [dep.Package] {

    return try get(specs.map{ ($0.url, $0.versionRange) }, prefix: prefix)

    //TODO normalize urls eg http://github.com -> https://github.com
    //TODO probably should respect any relocation that applies during git transfer
    //TODO detect cycles?
}

public func get(urls: [String], prefix: String) throws -> [dep.Package] {
    return try get(urls.map{ ($0, Version.maxRange) }, prefix: prefix)
}

public func get(urls: [(String, Range<Version>)], prefix: String) throws -> [dep.Package] {
    return try Sandbox(prefix: prefix).recursivelyFetch(urls)
}

/**
 MARK: Fetcher Protocols
 
 Testable protocol to recursively fetch versioned resources.
 Our usage fetches remote packages by having Sandbox conform.
*/
protocol Fetcher {
    typealias T: Fetchable

    func find(url url: String) throws -> Fetchable?
    func fetch(url url: String) throws -> Fetchable
    func finalize(fetchable: Fetchable) throws -> T

    func recursivelyFetch(urls: [(String, Range<Version>)]) throws -> [T]
}

protocol Fetchable {
    var version: Version { get }
    var dependencies: [(String, Range<Version>)] { get }

    /**
     This should be a separate protocol. But Swift 2 was not happy
     with the result since `U: T` this upset the type system when
     we needed to collect U as T. FIXME
    */
    var availableVersions: [Version] { get }

    func constrain(to versionRange: Range<Version>) -> Version?

    //FIXME protocols cannot impose new property constraints,
    // so Package has a version { get } already, we cannot add
    // a set, so instead we hve to have this protocol func
    func setVersion(newValue: Version) throws
}


/**
 MARK: Sandbox (Fetcher Implementation)

 Implementation detail: a container for fetched packages.
*/
class Sandbox {
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }
}

extension Sandbox: Fetcher {
    typealias T = Package

    func find(url url: String) throws -> Fetchable? {
        for prefix in walk(self.prefix, recursively: false) {
            guard let repo = Git.Repo(root: prefix) else { continue }  //TODO warn user
            guard repo.origin == url else { continue }
            return try Package(path: prefix)
        }
        return nil
    }

    func fetch(url url: String) throws -> Fetchable {
        let dstdir = Path.join(prefix, Package.name(forURL: url))
        if let repo = Git.Repo(root: dstdir) where repo.origin == url {
            //TODO need to canolicanize the URL need URL struct
            return try RawClone(path: dstdir)
        }
        try Git.clone(url, to: dstdir)

        // fetch as well, clone does not fetch all tags, only tags on the master branch
        try system("git", "-C", dstdir, "fetch", "origin")

        return try RawClone(path: dstdir)
    }

    func finalize(fetchable: Fetchable) throws -> Package {
        switch fetchable {
        case let clone as RawClone:
            let prefix = Path.join(self.prefix, Package.name(forURL: clone.url, version: clone.version))
            try mkdir(prefix)
            try rename(old: clone.path, new: prefix)
            return try Package(path: prefix)!
        case let pkg as Package:
            return pkg
        default:
            fatalError("Unexpected Fetchable Type: \(fetchable)")
        }
    }

    /**
     Initially we clone into a non-final form because we may need to
     adjust the dependency graph due to further specifications as
     we clone more repositories. This is the non-final form. Once
     `recursivelyFetch` completes we finalize these clones into our
     Sandbox.
     */
    class RawClone: Fetchable {
        let path: String
        let manifest: Manifest!

        init(path: String) throws {
            self.path = path
            do {
                let manifestPath = Path.join(path, Manifest.filename)
                self.manifest = try Manifest(path: manifestPath, baseURL: Git.Repo(root: path)!.origin!)
            } catch {
                self.manifest = nil
                throw error
            }
        }

        var repo: Git.Repo {
            return Git.Repo(root: path)!
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
        func setVersion(v: Version) throws {
            let packageVersionsArePrefixed = repo.versionsArePrefixed
            let v = (packageVersionsArePrefixed ? "v" : "") + v.description
            try popen([Git.tool, "-C", path, "reset", "--hard", v])
            try popen([Git.tool, "-C", path, "branch", "-m", v])
        }

        func constrain(to versionRange: Range<Version>) -> Version? {
            return availableVersions.filter {
                // not using `contains` as it uses successor() and for Range<Version>
                // this involves iterating from 0 to Int.max!
                if case versionRange = $0 { return true } else { return false }
            }.last
        }

        var dependencies: [(String, Range<Version>)] {
            //COPY PASTA from Package.dependencies
            return manifest.package.dependencies.map{ ($0.url, $0.versionRange) }
        }

        var url: String {
            return repo.origin ?? "BAD_ORIGIN"
        }

        var availableVersions: [Version] {
            return repo.versions
        }
    }
}

extension Package: Fetchable {
    var dependencies: [(String, Range<Version>)] {
        return manifest.package.dependencies.map{ ($0.url, $0.versionRange) }
    }
    func constrain(to versionRange: Range<Version>) -> Version? {
        return nil
    }
    var availableVersions: [Version] {
        return [version]
    }
    func setVersion(newValue: Version) throws {
        throw Error.InvalidDependencyGraph(url)
    }
}


//MARK: Core Logic

extension Fetcher {
    /**
     Recursively fetch remote, versioned resources.
    */
    func recursivelyFetch(urls: [(String, Range<Version>)]) throws -> [T] {
        var graph = [String: (Fetchable, Range<Version>)]()

        func recurse(urls: [(String, Range<Version>)]) throws -> [String] {

            return try urls.flatMap { url, specifiedVersionRange -> [String] in

                func adjust(pkg: Fetchable, _ versionRange: Range<Version>) throws {
                    guard let v = pkg.constrain(to: versionRange) else {
                        throw Error.InvalidDependencyGraph(url)
                    }
                    try pkg.setVersion(v)
                }

                if let (pkg, cumulativeVersionRange) = graph[url] {

                    // this package has already been checked out this instantiation
                    // verify that it satisfies the requested version range

                    guard let updatedRange = cumulativeVersionRange.constrain(to: specifiedVersionRange) else {
                        throw Error.InvalidDependencyGraph(url)
                    }

                    if updatedRange ~= pkg.version {

                        // the current checked-out version is within the requested range

                        graph[url] = (pkg, updatedRange)
                        return []

                    } else {

                        // we cloned this package this instantiation, let’s attempt to
                        // modify its checkout

                        try adjust(pkg, updatedRange)
                        graph[url] = (pkg, updatedRange)

                        //FIXME we need to rewind and re-read this manifest and start again from there
                        return []
                    }

                } else if let pkg = try self.find(url: url) {

                    // this package was already installed from a previous instantiation
                    // of the package manager. Verify it is within the required version
                    // range.

                    guard specifiedVersionRange ~= pkg.version else {
                        throw Error.UpdateRequired(url)
                    }
                    graph[url] = (pkg, specifiedVersionRange)
                    return try recurse(pkg.dependencies) + [url]

                } else {

                    // clone the package

                    let clone = try self.fetch(url: url)
                    try adjust(clone, specifiedVersionRange)
                    graph[url] = (clone, specifiedVersionRange)
                    return try recurse(clone.dependencies) + [url]
                }
            }
        }

        return try recurse(urls).map{ graph[$0]!.0 }.map{ try self.finalize($0) }
    }
}


//MARK: detritus

extension Range where Element: BidirectionalIndexType, Element: Comparable {

    /**
     - Returns: A new Range with startIndex and endIndex constrained such that
     the returned range is entirely withing this Range and the provided Range.
     If the two ranges do not overlap at all returns `nil`.
    */
    func constrain(to constraint: Range) -> Range? {
        guard self ~= constraint.endIndex.predecessor() || self ~= constraint.startIndex else {
            return nil
        }

        let lhs = constraint
        let rhs = self
        let start = [lhs.startIndex, rhs.startIndex].maxElement()!
        let end = [lhs.endIndex, rhs.endIndex].minElement()!
        return start..<end
    }
}
