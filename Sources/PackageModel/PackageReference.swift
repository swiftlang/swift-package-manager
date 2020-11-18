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

    /// Compute the default name of a package given its URL.
    public static func computeDefaultName(fromURL url: String) -> String {
      #if os(Windows)
        let isSeparator : (Character) -> Bool = { $0 == "/" || $0 == "\\" }
      #else
        let isSeparator : (Character) -> Bool = { $0 == "/" }
      #endif

        // Get the last path component of the URL.
        // Drop the last character in case it's a trailing slash.
        var endIndex = url.endIndex
        if let lastCharacter = url.last, isSeparator(lastCharacter) {
            endIndex = url.index(before: endIndex)
        }

        let separatorIndex = url[..<endIndex].lastIndex(where: isSeparator)
        let startIndex = separatorIndex.map { url.index(after: $0) } ?? url.startIndex
        var lastComponent = url[startIndex..<endIndex]

        // Strip `.git` suffix if present.
        if lastComponent.hasSuffix(".git") {
            lastComponent = lastComponent.dropLast(4)
        }

        return String(lastComponent)
    }

    /// The identity of the package.
    public let identity: PackageIdentity

    /// The name of the package, if available.
    public var name: String {
        _name ?? Self.computeDefaultName(fromURL: path)
    }
    private let _name: String?

    /// The path of the package.
    ///
    /// This could be a remote repository, local repository or local package.
    public let path: String

    /// The kind of package: root, local, or remote.
    public let kind: Kind

    /// Create a package reference given its identity and repository.
    public init(identity: PackageIdentity, path: String, name: String? = nil, kind: Kind = .remote) {
        self._name = name
        self.identity = identity
        self.path = path
        self.kind = kind
    }

    /// Create a new package reference object with the given name.
    public func with(newName: String) -> PackageReference {
        return PackageReference(identity: identity, path: path, name: newName, kind: kind)
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
        self._name = json.get("name")
        self.identity = try json.get("identity")
        self.path = try json.get("path")

        // Support previous version of PackageReference that contained an `isLocal` property.
        if let isLocal: Bool = json.get("isLocal") {
            kind = isLocal ? .local : .remote
        } else {
            kind = try Kind(rawValue: json.get("kind"))!
        }
    }

    public func toJSON() -> JSON {
        return .init([
            "name": name.toJSON(),
            "identity": identity,
            "path": path,
            "kind": kind.rawValue,
        ])
    }
}
