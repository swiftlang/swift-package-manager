/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageGraph
import SourceControl
import Utility

/// A checkout state represents the current state of a repository.
///
/// A state will always has a revision. It can also have a branch or a version but not both.
public struct CheckoutState: Equatable {

    /// The revision of the checkout.
    public let revision: Revision

    /// The version of the checkout, if known.
    public let version: Version?

    /// The branch of the checkout, if known.
    public let branch: String?

    /// Create a checkout state with given data. It is invalid to provide both version and branch.
    ///
    /// This is deliberately fileprivate so CheckoutState is not initialized
    /// with both version and branch. All other initializers should delegate to it.
    fileprivate init(revision: Revision, version: Version?, branch: String?) {
        assert(version == nil || branch == nil, "Can't set both branch and version.")
        self.revision = revision
        self.version = version
        self.branch = branch
    }

    /// Create a checkout state with given revision and branch.
    public init(revision: Revision, branch: String? = nil) {
        self.init(revision: revision, version: nil, branch: branch)
    }

    /// Create a checkout state with given revision and version.
    public init(revision: Revision, version: Version) {
        self.init(revision: revision, version: version, branch: nil)
    }

    public var description: String {
        return version?.description ?? branch ?? revision.identifier
    }

    public static func == (lhs: CheckoutState, rhs: CheckoutState) -> Bool {
        return lhs.revision == rhs.revision &&
               lhs.version == rhs.version &&
               lhs.branch == rhs.branch
    }
}

extension CheckoutState {

    /// Returns requirement induced by this state.
    func requirement() -> RepositoryPackageConstraint.Requirement {
        if let version = version {
            return .versionSet(.exact(version))
        } else if let branch = branch {
            return .revision(branch)
        }
        return .revision(revision.identifier)
    }
}

// MARK: - JSON

extension CheckoutState: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
       self.init(
           revision: try json.get("revision"),
           version: json.get("version"),
           branch: json.get("branch")
        )
    }

    public func toJSON() -> JSON {
       return .init([
           "revision": revision.identifier,
           "version": version.toJSON(),
           "branch": branch.toJSON(),
       ])
    }
}
