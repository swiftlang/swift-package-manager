/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

/// A package reference.
///
/// This represents a reference to a package containing its identity and location.
public struct PackageReference: Codable {
    /// The kind of package reference.
    public enum Kind: String, Codable {
        /// A root package.
        case root

        /// A non-root local package.
        case local

        /// A remote package.
        case remote
    }

    /// The identity of the package.
    public let identity: PackageIdentity

    /// The path of the package.
    ///
    /// This could be a remote repository, local repository or local package.
    public let path: String

    /// The kind of package: root, local, or remote.
    public let kind: Kind

    // FIXME
    /// An alternate identity of the package.
    /// This would be deprecated when identity refactoring is complete.
    /// Right now, there is a way to "override" the identity of
    /// the package from the name in the manifest, this is a crutch until we remove
    /// the name from the manifest all together
    private let _alternateIdentity: PackageIdentity?

    public var alternateIdentity: PackageIdentity? {
        get {
            self._alternateIdentity
        }
    }

    /// Create a package reference given its identity and repository.
    public init(identity: PackageIdentity, path: String, kind: Kind = .remote) {
        self.identity = identity
        self.path = path
        self.kind = kind
        self._alternateIdentity = nil
    }

    private init(identity: PackageIdentity, path: String, kind: Kind = .remote, alternateIdentity: PackageIdentity?) {
        self.identity = identity
        self.path = path
        self.kind = kind
        self._alternateIdentity = alternateIdentity != identity ? alternateIdentity : nil
    }

    // FIXME: the purpose of this is to allow identity override based on the identity in the manifest which is hacky
    // this should be removed when we remove name from manifest
    /// Create a new package reference object with the given identity.
    public func with(alternateIdentity: PackageIdentity) -> PackageReference {
        return PackageReference(identity: identity, path: path, kind: kind, alternateIdentity: alternateIdentity)
    }

    public static func root(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, path: path.pathString, kind: .root)
    }

    public static func local(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, path: path.pathString, kind: .local)
    }

    public static func remote(identity: PackageIdentity, url: String) -> PackageReference {
        PackageReference(identity: identity, path: url, kind: .remote)
    }
}

extension PackageReference: Equatable {
    public static func ==(lhs: PackageReference, rhs: PackageReference) -> Bool {
        return lhs.identity == rhs.identity
    }
}

extension PackageReference: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}

extension PackageReference: CustomStringConvertible {
    public var description: String {
        return "\(identity)\(path.isEmpty ? "" : "[\(path)]")"
    }
}

extension PackageReference: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        self.identity = try json.get("identity")
        self.path = try json.get("path")

        // Support previous version of PackageReference that contained an `isLocal` property.
        if let isLocal: Bool = json.get("isLocal") {
            self.kind = isLocal ? .local : .remote
        } else {
            self.kind = try Kind(rawValue: json.get("kind"))!
        }

        // backwards compatibility 12/2020
        if let identity: PackageIdentity = json.get("alternateIdentity") {
            self._alternateIdentity = identity
        } else if let identity: PackageIdentity = json.get("name") {
            self._alternateIdentity = identity
        } else {
            self._alternateIdentity = nil
        }
    }

    public func toJSON() -> JSON {
        var map: [String: JSONSerializable] = [
            "identity": self.identity,
            "path": self.path,
            "kind": self.kind.rawValue
        ]
        if let identity = self._alternateIdentity {
            map["alternateIdentity"] = identity
        }
        return .init(map)
    }
}
