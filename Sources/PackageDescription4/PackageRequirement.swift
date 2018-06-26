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
      #if PACKAGE_DESCRIPTION_4_2
        return ._exactItem(version)
      #else
        return .exactItem(version)
      #endif
    }

    /// The requirement is specified by a source control revision.
    public static func revision(_ ref: String) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4_2
        return ._revisionItem(ref)
      #else
        return .revisionItem(ref)
      #endif
    }

    /// The requirement is specified by a source control branch.
    public static func branch(_ name: String) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4_2
        return ._branchItem(name)
      #else
        return .branchItem(name)
      #endif
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next major version.
    public static func upToNextMajor(from version: Version) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4_2
        return ._rangeItem(version..<Version(version.major + 1, 0, 0))
      #else
        return .rangeItem(version..<Version(version.major + 1, 0, 0))
      #endif
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next minor version.
    public static func upToNextMinor(from version: Version) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4_2
        return ._rangeItem(version..<Version(version.major, version.minor + 1, 0))
      #else
        return .rangeItem(version..<Version(version.major, version.minor + 1, 0))
      #endif
    }

    func toJSON() -> JSON {
      #if PACKAGE_DESCRIPTION_4_2
        switch self {
        case ._rangeItem(let range):
            return .dictionary([
                "type": .string("range"),
                "lowerBound": .string(range.lowerBound.description),
                "upperBound": .string(range.upperBound.description),
            ])
        case ._exactItem(let version):
            return .dictionary([
                "type": .string("exact"),
                "identifier": .string(version.description),
            ])
        case ._branchItem(let identifier):
            return .dictionary([
                "type": .string("branch"),
                "identifier": .string(identifier),
            ])
        case ._revisionItem(let identifier):
            return .dictionary([
                "type": .string("revision"),
                "identifier": .string(identifier),
            ])
        case ._localPackageItem:
            return .dictionary([
                "type": .string("localPackage"),
            ])
        }
      #else
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
        case .localPackageItem:
            return .dictionary([
                "type": .string("localPackage"),
            ])
        }
      #endif
    }
}
