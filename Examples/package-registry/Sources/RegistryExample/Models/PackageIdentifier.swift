//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Errors that can be thrown when constructing a ``PackageIdentifier``.
///
/// These correspond to the scope and name validity rules in §3.6 of the
/// Swift Package Registry Service Specification.
public enum PackageIdentifierError: Error, Equatable, Sendable {
    /// The provided scope did not match the pattern
    /// `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z` (§3.6.1).
    case invalidScope

    /// The provided name did not match the pattern
    /// `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|[-_](?=[a-zA-Z0-9])){0,99}\z` (§3.6.2).
    case invalidName
}

/// A scoped package identifier of the form `scope.name`, as defined by
/// §3.6 of the Swift Package Registry Service Specification.
///
/// A package identifier combines a *scope* (a namespace for related
/// packages, §3.6.1) with a *name* (unique within its scope, §3.6.2):
///
/// - **Scope**: 1-39 alphanumeric characters and hyphens. Hyphens may not
///   appear at either end nor consecutively. Matches
///   `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}\z`.
/// - **Name**: 1-100 alphanumeric characters, hyphens, and underscores.
///   Hyphens and underscores may not appear at either end nor
///   consecutively. Matches
///   `\A[a-zA-Z0-9](?:[a-zA-Z0-9]|[-_](?=[a-zA-Z0-9])){0,99}\z`.
///
/// Both components are case-insensitive, so `mona.LinkedList` and
/// `MONA.linkedlist` refer to the same package. This is reflected in
/// ``==(_:_:)``, ``hash(into:)``, and ``storageKey``, while the original
/// casing supplied at construction time is preserved in ``scope`` and
/// ``name`` for display purposes.
public struct PackageIdentifier: Hashable, Sendable, CustomStringConvertible {
    /// The package scope, preserving the casing supplied at construction
    /// time. Use ``storageKey`` for a case-normalized lookup key.
    public let scope: String

    /// The package name within ``scope``, preserving the casing supplied at
    /// construction time. Use ``storageKey`` for a case-normalized lookup
    /// key.
    public let name: String

    /// Creates a validated package identifier.
    ///
    /// - Parameters:
    ///   - scope: The package scope (§3.6.1). Must match the scope grammar.
    ///   - name: The package name (§3.6.2). Must match the name grammar.
    /// - Throws: ``PackageIdentifierError/invalidScope`` if `scope` does not
    ///   satisfy the §3.6.1 grammar, or
    ///   ``PackageIdentifierError/invalidName`` if `name` does not satisfy
    ///   the §3.6.2 grammar.
    public init(scope: String, name: String) throws {
        guard Self.isValidScope(scope) else {
            throw PackageIdentifierError.invalidScope
        }
        guard Self.isValidName(name) else {
            throw PackageIdentifierError.invalidName
        }
        self.scope = scope
        self.name = name
    }

    /// A case-normalized key suitable for use as a storage or cache key.
    ///
    /// Both ``scope`` and ``name`` are lowercased and joined with a dot, so
    /// that identifiers differing only in case (for example,
    /// `Mona.LinkedList` and `mona.linkedlist`) map to the same key, in
    /// line with the case-insensitivity rules of §3.6.
    public var storageKey: String {
        "\(scope.lowercased()).\(name.lowercased())"
    }

    /// The canonical `scope.name` string representation of the identifier,
    /// preserving the original casing of both components.
    public var description: String {
        "\(scope).\(name)"
    }

    /// Compares two identifiers for equality using the case-insensitive
    /// rules defined in §3.6.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand identifier.
    ///   - rhs: The right-hand identifier.
    /// - Returns: `true` if the two identifiers refer to the same package
    ///   when compared case-insensitively.
    public static func == (lhs: PackageIdentifier, rhs: PackageIdentifier) -> Bool {
        lhs.scope.lowercased() == rhs.scope.lowercased()
            && lhs.name.lowercased() == rhs.name.lowercased()
    }

    /// Hashes the case-normalized form of the identifier, so that the hash
    /// is consistent with case-insensitive equality.
    ///
    /// - Parameter hasher: The hasher to feed the normalized components
    ///   into.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(scope.lowercased())
        hasher.combine(name.lowercased())
    }

    static func isValidScope(_ s: String) -> Bool {
        validate(s, maxLength: 39) { $0 == "-" }
    }

    static func isValidName(_ s: String) -> Bool {
        validate(s, maxLength: 100) { $0 == "-" || $0 == "_" }
    }

    private static func validate(
        _ s: String,
        maxLength: Int,
        isConnector: (Character) -> Bool
    ) -> Bool {
        guard !s.isEmpty, s.count <= maxLength else { return false }
        var previousWasConnector = false
        for (index, ch) in s.enumerated() {
            let isAlnum = ch.isASCII && (ch.isLetter || ch.isNumber)
            if isAlnum {
                previousWasConnector = false
                continue
            }
            if isConnector(ch) {
                if index == 0 || index == s.count - 1 { return false }
                if previousWasConnector { return false }
                previousWasConnector = true
                continue
            }
            return false
        }
        return true
    }
}
