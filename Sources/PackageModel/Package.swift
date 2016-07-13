/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import struct PackageDescription.Version

public final class Package {
    /// The name of the package.
    public let name: String
    
    /// The URL the package was loaded from.
    //
    // FIXME: This probably doesn't belong here...
    public let url: String
    
    /// The local path of the package.
    public let path: String

    /// The manifest describing the package.
    public let manifest: Manifest

    /// The version this package was loaded from, if known.
    //
    // FIXME: Eliminate this method forward.
    public var version: Version? {
        return manifest.version
    }

    /// The resolved dependencies of the package.
    ///
    /// This value is only available once package loading is complete.
    public var dependencies: [Package] = []

    public init(manifest: Manifest, url: String) {
        self.url = url
        self.manifest = manifest
        self.path = manifest.path.parentDirectory
        self.name = manifest.package.name ?? Package.nameForURL(url)
    }

    public enum Error: Swift.Error {
        case noManifest(String)
        case noOrigin(String)
    }
}

extension Package: CustomStringConvertible {
    public var description: String {
        return name
    }
}

extension Package: Hashable, Equatable {
    public var hashValue: Int { return ObjectIdentifier(self).hashValue }
}

public func ==(lhs: Package, rhs: Package) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

extension Package {
    public static func nameForURL(_ url: String) -> String {
        let base = url.basename

        switch URL.scheme(url) ?? "" {
        case "http", "https", "git", "ssh":
            if url.hasSuffix(".git") {
                let a = base.startIndex
                let b = base.index(base.endIndex, offsetBy: -4)
                return base[a..<b]
            } else {
                fallthrough
            }
        default:
            return base
        }
    }
}
