/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import SourceControl
import TSCUtility

/// A checkout state represents the current state of a repository.
///
/// A state will always has a revision. It can also have a branch or a version but not both.
public enum CheckoutState: Equatable, Hashable {

    case revision(Revision)
    case version(Version, revision: Revision)
    case branch(String, revision: Revision)

    /// The revision of the checkout.
    public var revision: Revision {
        get {
            switch self {
            case .revision(let revision):
                return revision
            case .version(_, let revision):
                return revision
            case .branch(_, let revision):
                return revision
            }
        }
    }

    public var isBranchOrRevisionBased: Bool {
        switch self {
        case .revision, .branch:
            return true
        case .version:
            return false
        }
    }

    /// Returns requirement induced by this state.
    public var requirement: PackageRequirement {
        switch self {
        case .revision(let revision):
            return .revision(revision.identifier)
        case .version(let version, _):
            return .versionSet(.exact(version))
        case .branch(let branch, _):
            return .revision(branch)
        }
    }
}

// MARK: - CustomStringConvertible

extension CheckoutState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .revision(let revision):
            return revision.identifier
        case .version(let version, _):
            return version.description
        case .branch(let branch, _):
            return branch
        }
    }
}

// MARK: - JSON

extension CheckoutState: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        let revision: Revision = try json.get("revision")
        let version: Version? = json.get("version")
        let branch: String? = json.get("branch")

        switch (version, branch) {
        case (.none, .none):
            self = .revision(revision)
        case (.some(let version), .none):
            self = .version(version, revision: revision)
        case (.none, .some(let branch)):
            self = .branch(branch, revision: revision)
        case (.some(_), .some(_)):
            preconditionFailure("Can't set both branch and version.")
        }
    }

    public func toJSON() -> JSON {
        let revision: Revision
        let version: Version?
        let branch: String?

        switch self {
        case .revision(let _revision):
            revision = _revision
            version = nil
            branch = nil
        case .version(let _version, let _revision):
            revision = _revision
            version = _version
            branch = nil
        case .branch(let _branch, let _revision):
            revision = _revision
            version = nil
            branch = _branch
        }

        return .init([
            "revision": revision.identifier,
            "version": version.toJSON(),
            "branch": branch.toJSON(),
        ])
    }
}

