/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Package.Dependency.Requirement: Encodable {

    /// The requirement is specified by an exact version.
    public static func exact(_ version: Version) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4
        return .exactItem(version)
      #else
        return ._exactItem(version)
      #endif
    }

    /// The requirement is specified by a source control revision.
    public static func revision(_ ref: String) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4
        return .revisionItem(ref)
      #else
        return ._revisionItem(ref)
      #endif
    }

    /// The requirement is specified by a source control branch.
    public static func branch(_ name: String) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4
        return .branchItem(name)
      #else
        return ._branchItem(name)
      #endif
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next major version.
    public static func upToNextMajor(from version: Version) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4
        return .rangeItem(version..<Version(version.major + 1, 0, 0))
      #else
        return ._rangeItem(version..<Version(version.major + 1, 0, 0))
      #endif
    }

    /// Creates a specified for a range starting at the given lower bound
    /// and going upto next minor version.
    public static func upToNextMinor(from version: Version) -> Package.Dependency.Requirement {
      #if PACKAGE_DESCRIPTION_4
        return .rangeItem(version..<Version(version.major, version.minor + 1, 0))
      #else
        return ._rangeItem(version..<Version(version.major, version.minor + 1, 0))
      #endif
    }

    private enum CodingKeys: CodingKey {
        case type
        case lowerBound
        case upperBound
        case identifier
    }

    private enum Kind: String, Codable {
        case range
        case exact
        case branch
        case revision
        case localPackage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
      #if PACKAGE_DESCRIPTION_4
        switch self {
        case .rangeItem(let range):
            try container.encode(Kind.range, forKey: .type)
            try container.encode(range.lowerBound, forKey: .lowerBound)
            try container.encode(range.upperBound, forKey: .upperBound)
        case .exactItem(let version):
            try container.encode(Kind.exact, forKey: .type)
            try container.encode(version, forKey: .identifier)
        case .branchItem(let identifier):
            try container.encode(Kind.branch, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case .revisionItem(let identifier):
            try container.encode(Kind.revision, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case .localPackageItem:
            try container.encode(Kind.localPackage, forKey: .type)
        }
      #else
        switch self {
        case ._rangeItem(let range):
            try container.encode(Kind.range, forKey: .type)
            try container.encode(range.lowerBound, forKey: .lowerBound)
            try container.encode(range.upperBound, forKey: .upperBound)
        case ._exactItem(let version):
            try container.encode(Kind.exact, forKey: .type)
            try container.encode(version, forKey: .identifier)
        case ._branchItem(let identifier):
            try container.encode(Kind.branch, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case ._revisionItem(let identifier):
            try container.encode(Kind.revision, forKey: .type)
            try container.encode(identifier, forKey: .identifier)
        case ._localPackageItem:
            try container.encode(Kind.localPackage, forKey: .type)
        }
      #endif
    }
}
