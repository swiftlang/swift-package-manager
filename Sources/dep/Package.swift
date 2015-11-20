/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version
import POSIX
import sys

/**
 A collection of sources that can be built into products.

 For our purposes we always have a local path for the
 package because we cannot interpret anything about it
 without having cloned and read its manifest first.

 In order to get the list of packages that this package
 depends on you need to map them from the `manifest`.
*/
public struct Package {
    /// the local clone
    public let path: String

    public let manifest: Manifest

    /// the semantic version of this package
    public let version: Version

    /**
      - Returns: The Package or this doesn’t seem to be a Package, nil.
      - Note: Throws if the Package manifest will not parse.
     */
    public init?(path: String) throws {
        // Packages are git clones
        guard let repo = Git.Repo(root: path) else { return nil }

        // Packages have origins
        guard let origin = repo.origin else { return nil }

        // Packages have dirnames of the form foo-X.Y.Z
        let parts = path.basename.characters.split("-")
        guard parts.count >= 2 else { return nil }
        guard let version = Version(parts.last!) else { return nil }

        self.version = version
        self.manifest = try Manifest(path: Path.join(path, Manifest.filename), baseURL: origin)
        self.path = try path.abspath()
    }

    /// where we came from
    public var url: String {
        return Git.Repo(root: path)!.origin!
    }

    /**
     The targets of this package, computed using our convention-layot rules
     and mapping the result over the Manifest specifications.
     */
    public func targets() throws -> [Target] {
        if type == .ModuleMap { return [] }  //TODO P.O.P.

        let computedTargets = try determineTargets(packageName: name, prefix: path)
        return try manifest.configureTargets(computedTargets)
    }

    /// The package’s name; either computed from the url or provided by the Manifest.
    public var name: String {
        return manifest.package.name ?? Package.name(forURL: url)
    }

    /// - Returns: The name that would be determined from the provided URL.
    static func name(forURL url: String) -> String {
        let base = url.basename

        switch URL.scheme(url) ?? "" {
        case "http", "https", "git", "ssh":
            if url.hasSuffix(".git") {
                let a = base.startIndex
                let b = base.endIndex.advancedBy(-4)
                return base[a..<b]
            } else {
                fallthrough
            }
        default:
            return base
        }
    }

    /// - Returns: The name that would be determined from the provided URL and version.
    static func name(forURL url: String, version: Version) -> String {
        return "\(name(forURL: url))-\(version)"
    }

    public enum Type {
        case Module
        case ModuleMap
    }

    public var type: Type {
        if Path.join(path, "module.modulemap").isFile {
            return .ModuleMap
        } else {
            return .Module
        }
    }
}

extension Package: CustomStringConvertible {
    public var description: String {
        return "Package(\(url) \(version))"
    }
}
