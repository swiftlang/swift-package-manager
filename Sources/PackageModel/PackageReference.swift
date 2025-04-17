//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

/// A package reference.
///
/// This represents a reference to a package containing its identity and location.
public struct PackageReference {
    /// The kind of package reference.
    public enum Kind: Hashable, CustomStringConvertible, Sendable {
        /// A root package.
        case root(AbsolutePath)

        /// A non-root local package.
        case fileSystem(AbsolutePath)

        /// A local source package.
        case localSourceControl(AbsolutePath)

        /// A remote source package.
        case remoteSourceControl(SourceControlURL)

        /// A package from  a registry.
        case registry(PackageIdentity)

        // FIXME: we should not need this once we migrate off URLs
        //@available(*, deprecated)
        public var locationString: String {
            switch self {
            case .root(let path):
                return path.pathString
            case .fileSystem(let path):
                return path.pathString
            case .localSourceControl(let path):
                return path.pathString
            case .remoteSourceControl(let url):
                return url.absoluteString
            case .registry(let identity):
                // FIXME: this is a placeholder
                return identity.description
            }
        }

        // FIXME: we should not need this once we migrate off URLs
        //@available(*, deprecated)
        public var canonicalLocation: CanonicalPackageLocation {
            return CanonicalPackageLocation(self.locationString)
        }

        public var description: String {
            switch self {
            case .root(let path):
                return "root \(path)"
            case .fileSystem(let path):
                return "fileSystem \(path)"
            case .localSourceControl(let path):
                return "localSourceControl \(path)"
            case .remoteSourceControl(let url):
                return "remoteSourceControl \(url)"
            case .registry(let identity):
                return "registry \(identity)"
            }
        }

        // FIXME: ideally this would not be required and we can check on the enum directly
        public var isRoot: Bool {
            if case .root = self {
                return true
            } else {
                return false
            }
        }
    }

    /// The identity of the package.
    public let identity: PackageIdentity

    /// The name of the package, if available.
    // soft deprecated 11/21
    public private(set) var deprecatedName: String

    /// The location of the package.
    ///
    /// This could be a remote repository, local repository or local package.
    // FIXME: we should not need this once we migrate off URLs
    //@available(*, deprecated)
    public var locationString: String {
        self.kind.locationString
    }

    // FIXME: we should not need this once we migrate off URLs
    //@available(*, deprecated)
    public var canonicalLocation: CanonicalPackageLocation {
        self.kind.canonicalLocation
    }

    /// The kind of package: root, local, or remote.
    public let kind: Kind

    /// Create a package reference given its identity and kind.
    public init(identity: PackageIdentity, kind: Kind, name: String? = nil) {
        self.identity = identity
        self.kind = kind
        switch kind {
        case .root(let path):
            self.deprecatedName = name ?? PackageIdentityParser.computeDefaultName(fromPath: path)
        case .fileSystem(let path):
            self.deprecatedName = name ?? PackageIdentityParser.computeDefaultName(fromPath: path)
        case .localSourceControl(let path):
            self.deprecatedName = name ?? PackageIdentityParser.computeDefaultName(fromPath: path)
        case .remoteSourceControl(let url):
            self.deprecatedName = name ?? PackageIdentityParser.computeDefaultName(fromURL: url)
        case .registry(let identity):
            // FIXME: this is a placeholder
            self.deprecatedName = name ?? identity.description
        }
    }

    /// Create a new package reference object with the given name.
    public func withName(_ newName: String) -> PackageReference {
        return PackageReference(identity: self.identity, kind: self.kind, name: newName)
    }

    public static func root(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, kind: .root(path))
    }

    public static func fileSystem(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, kind: .fileSystem(path))
    }

    public static func localSourceControl(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, kind: .localSourceControl(path))
    }

    public static func remoteSourceControl(identity: PackageIdentity, url: SourceControlURL) -> PackageReference {
        PackageReference(identity: identity, kind: .remoteSourceControl(url))
    }

    public static func registry(identity: PackageIdentity) -> PackageReference {
        PackageReference(identity: identity, kind: .registry(identity))
    }
}

extension PackageReference: Equatable {
    // TODO: consider location as well?
    public static func ==(lhs: PackageReference, rhs: PackageReference) -> Bool {
        return lhs.identity == rhs.identity
    }

    // TODO: consider rolling into Equatable
    public func equalsIncludingLocation(_ other: PackageReference) -> Bool {
        if self.identity != other.identity {
            return false
        }
        if self.canonicalLocation != other.canonicalLocation {
            return false
        }
        switch (self.kind, other.kind) {
        case (.remoteSourceControl(let lurl), .remoteSourceControl(let rurl)):
            return lurl.canonicalURL == rurl.canonicalURL
        default:
            return true
        }
    }
}

extension SourceControlURL {
    var canonicalURL: CanonicalPackageURL {
        CanonicalPackageURL(self.absoluteString)
    }
}

extension PackageReference: Hashable {
    // TODO: consider location as well?
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.identity)
    }
}

extension PackageReference {
    public var diagnosticsMetadata: ObservabilityMetadata {
        return .packageMetadata(identity: self.identity, kind: self.kind)
    }
}

extension PackageReference: CustomStringConvertible {
    public var description: String {
        return "\(self.identity) \(self.kind)"
    }
}

extension PackageReference.Kind: Encodable {
    private enum CodingKeys: String, CodingKey {
        case root, fileSystem, localSourceControl, remoteSourceControl, registry
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .root(let path):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .root)
            try unkeyedContainer.encode(path)
        case .fileSystem(let path):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .fileSystem)
            try unkeyedContainer.encode(path)
        case .localSourceControl(let path):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .localSourceControl)
            try unkeyedContainer.encode(path)
        case .remoteSourceControl(let url):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .remoteSourceControl)
            try unkeyedContainer.encode(url)
        case .registry:
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .registry)
            try unkeyedContainer.encode(self.isRoot)
        }
    }
}
