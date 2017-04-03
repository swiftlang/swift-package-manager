/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Package.Dependency.Requirement: Equatable {

    /// The requirement is specified by an exact version.
    public static func exact(_ version: Version) -> Package.Dependency.Requirement {
        return .exactItem(version)
    }

    /// The requirement is specified by a source control revision.
    public static func revision(_ ref: String) -> Package.Dependency.Requirement {
        return .revisionItem(ref)
    }

    /// The requirement is specified by a source control branch.
    public static func branch(_ name: String) -> Package.Dependency.Requirement {
        return .branchItem(name)
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next major version.
    public static func upToNextMajor(from version: Version) -> Package.Dependency.Requirement {
        return .rangeItem(version..<Version(version.major + 1, 0, 0))
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next minor version.
    public static func upToNextMinor(from version: Version) -> Package.Dependency.Requirement {
        return .rangeItem(version..<Version(version.major, version.minor + 1, 0))
    }

    public static func == (
        lhs: Package.Dependency.Requirement,
        rhs: Package.Dependency.Requirement
    ) -> Bool {
        switch (lhs, rhs) {
        case (.rangeItem(let lhs), .rangeItem(let rhs)):
            return lhs == rhs
        case (.rangeItem, _):
            return false
        case (.revisionItem(let lhs), .revisionItem(let rhs)):
            return lhs == rhs
        case (.revisionItem, _):
            return false
        case (.branchItem(let lhs), .branchItem(let rhs)):
            return lhs == rhs
        case (.branchItem, _):
            return false
        case (.exactItem(let lhs), .exactItem(let rhs)):
            return lhs == rhs
        case (.exactItem, _):
            return false
        }
    }

    func toJSON() -> JSON {
        switch self {
        case .rangeItem(let range):
            return .dictionary([
                "type": .string("range"),
                "lowerBound": .string(range.lowerBound.description),
                "upperBound": .string(range.upperBound.description),
            ])
        case .exactItem(let version):
            return .dictionary([
                "type": .string("exact"),
                "identifier": .string(version.description),
            ])
        case .branchItem(let identifier):
            return .dictionary([
                "type": .string("branch"),
                "identifier": .string(identifier),
            ])
        case .revisionItem(let identifier):
            return .dictionary([
                "type": .string("revision"),
                "identifier": .string(identifier),
            ])
        }
    }
}
