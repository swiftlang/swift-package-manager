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

    /// Compute identity of a package given its URL.
    public static func computeIdentity(packageURL: String) -> String {
        return PackageIdentity(packageURL).computedName
    }

    /// The identity of the package.
    public var identity: String {
        return self._identity.computedName.lowercased()
    }

    private let _identity: PackageIdentity

    /// The name of the package, if available.
    public var name: String {
        self._name ?? self._identity.computedName
    }

    private var _name: String?

    /// The path of the package.
    ///
    /// This could be a remote repository, local repository or local package.
    public let path: String

    /// The kind of package: root, local, or remote.
    public let kind: Kind

    /// Create a package reference given its identity and repository.
    public init(identity: String, path: String, name: String? = nil, kind: Kind = .remote) {
        self._identity = PackageIdentity(identity)
        self._name = name
        self.path = path
        self.kind = kind
    }

    /// Create a new package reference object with the given name.
    public func with(newName: String) -> PackageReference {
        var packageReference = self
        packageReference._name = newName
        return packageReference
    }
}

extension PackageReference: Equatable {
    public static func == (lhs: PackageReference, rhs: PackageReference) -> Bool {
        return lhs.identity == rhs.identity
    }
}

extension PackageReference: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.identity)
    }
}

extension PackageReference: CustomStringConvertible {
    public var description: String {
        return self.identity + (self.path.isEmpty ? "" : "[\(self.path)]")
    }
}

extension PackageReference: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        self._name = json.get("name")
        self._identity = try json.get("identity")
        self.path = try json.get("path")

        // Support previous version of PackageReference that contained an `isLocal` property.
        if let isLocal: Bool = json.get("isLocal") {
            self.kind = isLocal ? .local : .remote
        } else {
            self.kind = try Kind(rawValue: json.get("kind"))!
        }
    }

    public func toJSON() -> JSON {
        return .init([
            "name": self.name.toJSON(),
            "identity": self._identity,
            "path": self.path,
            "kind": self.kind.rawValue,
        ])
    }
}
