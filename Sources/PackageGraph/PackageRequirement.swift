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

/// A requirement that a package must satisfy.
public enum PackageRequirement: Hashable {

    /// The requirement is specified by the version set.
    case versionSet(VersionSetSpecifier)

    /// The requirement is specified by the revision.
    ///
    /// The revision string (identifier) should be valid and present in the
    /// container. Only one revision requirement per container is possible
    /// i.e. two revision requirements for same container will lead to
    /// unsatisfiable resolution. The revision requirement can either come
    /// from initial set of constraints or from dependencies of a revision
    /// requirement.
    case revision(String)

    /// Un-versioned requirement i.e. a version should not resolved.
    case unversioned
}

extension PackageRequirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .versionSet(let versionSet): return versionSet.description
        case .revision(let revision): return revision
        case .unversioned: return "unversioned"
        }
    }
}
