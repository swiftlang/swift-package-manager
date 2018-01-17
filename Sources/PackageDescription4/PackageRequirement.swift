/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Package.Dependency.Requirement {

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
