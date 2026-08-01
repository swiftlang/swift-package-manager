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
import struct TSCUtility.Version

/// A bound version for a package within an assignment.
public enum BoundVersion: Equatable, Hashable {
    /// The assignment should not include the package.
    ///
    /// This is different from the absence of an assignment for a particular
    /// package, which only indicates the assignment is agnostic to its
    /// version. This value signifies the package *may not* be present.
    case excluded

    /// The version of the package to include.
    case version(Version)

    /// The package assignment is unversioned.
    case unversioned

    /// The package assignment is this revision.
    case revision(String, branch: String? = nil)
}

extension BoundVersion {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.excluded, .excluded), (.unversioned, .unversioned):
            true
        case (.version(let lhs), .version(let rhs)):
            VersionIdentifierKey(lhs) == VersionIdentifierKey(rhs)
        case (.revision(let lhsRevision, let lhsBranch), .revision(let rhsRevision, let rhsBranch)):
            lhsRevision == rhsRevision && lhsBranch == rhsBranch
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .excluded:
            hasher.combine(0)
        case .version(let version):
            hasher.combine(1)
            hasher.combine(VersionIdentifierKey(version))
        case .unversioned:
            hasher.combine(2)
        case .revision(let revision, let branch):
            hasher.combine(3)
            hasher.combine(revision)
            hasher.combine(branch)
        }
    }
}

extension BoundVersion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .excluded:
            return "excluded"
        case .version(let version):
            return version.description
        case .unversioned:
            return "unversioned"
        case .revision(let identifier, _):
            return identifier
        }
    }
}
