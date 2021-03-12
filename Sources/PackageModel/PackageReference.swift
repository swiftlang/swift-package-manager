/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
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

    /// The name of the package, if available.
    public var name: String

    /// The path of the package.
    ///
    /// This could be a remote repository, local repository or local package.
    public let location: String

    /// The kind of package: root, local, or remote.
    public let kind: Kind

    /// Create a package reference given its identity and repository.
    public init(identity: PackageIdentity, kind: Kind, location: String, name: String? = nil) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.name = name ?? LegacyPackageIdentity.computeDefaultName(fromURL: location)
    }

    /// Create a new package reference object with the given name.
    public func with(newName: String) -> PackageReference {
        return PackageReference(identity: self.identity, kind: self.kind, location: self.location, name: newName)
    }

    public static func root(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, kind: .root, location: path.pathString)
    }

    public static func local(identity: PackageIdentity, path: AbsolutePath) -> PackageReference {
        PackageReference(identity: identity, kind: .local, location: path.pathString)
    }


    public static func remote(identity: PackageIdentity, location: String) -> PackageReference {
        PackageReference(identity: identity, kind: .remote, location: location)
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
        return "\(identity)\(self.location.isEmpty ? "" : "[\(self.location)]")"
    }
}

extension PackageReference: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        self.name = try json.get("name")
        self.identity = try json.get("identity")
        // Support previous version of PackageReference that contained an `path` property. 1/2021
        if let location: String = json.get("location") {
            self.location = location
        } else if let location: String = json.get("path") {
            self.location = location
        } else {
            throw InternalError("unknown package reference location")
        }

        // Support previous version of PackageReference that contained an `isLocal` property.
        if let isLocal: Bool = json.get("isLocal") {
            self.kind = isLocal ? .local : .remote
        } else {
            self.kind = try Kind(rawValue: json.get("kind"))!
        }
    }

    public func toJSON() -> JSON {
        return .init([
            "name": self.name,
            "identity": self.identity,
            "location": self.location,
            "kind": self.kind.rawValue,
        ])
    }
}
