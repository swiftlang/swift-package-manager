/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// Represents a package dependency.
public enum PackageDependencyDescription: Equatable {

     public struct Local: Equatable, Codable {
        public let identity: PackageIdentity
        public let name: String?
        public let path: AbsolutePath
        public let productFilter: ProductFilter
    }

    public struct SourceControlRepository: Equatable, Codable {
        public let identity: PackageIdentity
        public let name: String?
        public let location: String
        public let requirement: Requirement
        public let productFilter: ProductFilter
    }

    case local(Local)
    case scm(SourceControlRepository)
    //case registry(data: Registry) // for future

    /// The dependency requirement.
    public enum Requirement: Equatable, Hashable {
        case exact(Version)
        case range(Range<Version>)
        case revision(String)
        case branch(String)

        public static func upToNextMajor(from version: TSCUtility.Version) -> Requirement {
            return .range(version..<Version(version.major + 1, 0, 0))
        }

        public static func upToNextMinor(from version: TSCUtility.Version) -> Requirement {
            return .range(version..<Version(version.major, version.minor + 1, 0))
        }
    }

    public var identity: PackageIdentity {
        switch self {
        case .local(let data):
            return data.identity
        case .scm(let data):
            return data.identity
        }
    }

    // FIXME: we should simplify target based dependencies such that this is no longer required
    // A name to be used *only* for target dependencies resolution
    public var nameForTargetDependencyResolutionOnly: String {
        switch self {
        case .local(let data):
            return data.name ?? LegacyPackageIdentity.computeDefaultName(fromURL: data.path.pathString)
        case .scm(let data):
            return data.name ?? LegacyPackageIdentity.computeDefaultName(fromURL: data.location)
        }
    }

    // FIXME: we should simplify target based dependencies such that this is no longer required
    // A name to be used *only* for target dependencies resolution
    public var explicitNameForTargetDependencyResolutionOnly: String? {
        switch self {
        case .local(let data):
            return data.name
        case .scm(let data):
            return data.name
        }
    }

    public var productFilter: ProductFilter {
        switch self {
        case .local(let data):
            return data.productFilter
        case .scm(let data):
            return data.productFilter
        }
    }

    public var isLocal: Bool {
        switch self {
        case .local:
            return true
        case .scm:
            return false
        }
    }

    public func filtered(by productFilter: ProductFilter) -> PackageDependencyDescription {
        switch self {
        case .local(let data):
            return .local(identity: data.identity,
                          name: data.name,
                          path: data.path,
                          productFilter: productFilter)
        case .scm(let data):
            return .scm(identity: data.identity,
                        name: data.name,
                        location: data.location,
                        requirement: data.requirement,
                        productFilter: productFilter)
        }
    }

    public static func local(identity: PackageIdentity,
                             name: String?,
                             path: AbsolutePath,
                             productFilter: ProductFilter
    ) -> PackageDependencyDescription {
        .local (
            .init(identity: identity,
                  name: name,
                  path: path,
                  productFilter: productFilter)
        )
    }

    public static func scm(identity: PackageIdentity,
                           name: String?,
                           location: String,
                           requirement: Requirement,
                           productFilter: ProductFilter
    ) -> PackageDependencyDescription {
        .scm (
            .init(identity: identity,
                  name: name,
                  location: location,
                  requirement: requirement,
                  productFilter: productFilter)
        )
    }
}

extension PackageDependencyDescription: CustomStringConvertible {
    public var description: String {
        switch self {
        case .local(let data):
            return "local[\(data)]"
        case .scm(let data):
            return "git[\(data)]"
        }
    }
}

extension PackageDependencyDescription.Requirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exact(let version):
            return version.description
        case .range(let range):
            return range.description
        case .revision(let revision):
            return "revision[\(revision)]"
        case .branch(let branch):
            return "branch[\(branch)]"
        }
    }
}

extension PackageDependencyDescription: Codable {
    private enum CodingKeys: String, CodingKey {
        case local, scm
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let data):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .local)
            try unkeyedContainer.encode(data)
        case .scm(let data):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .scm)
            try unkeyedContainer.encode(data)

        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .local:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let data = try unkeyedValues.decode(Local.self)
            self = .local(data)
        case .scm:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let data = try unkeyedValues.decode(SourceControlRepository.self)
            self = .scm(data)
        }
    }
}

extension PackageDependencyDescription.Requirement: Codable {
    private enum CodingKeys: String, CodingKey {
        case exact, range, revision, branch
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .exact(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .exact)
            try unkeyedContainer.encode(a1)
        case let .range(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .range)
            try unkeyedContainer.encode(CodableRange(a1))
        case let .revision(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .revision)
            try unkeyedContainer.encode(a1)
        case let .branch(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .branch)
            try unkeyedContainer.encode(a1)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .exact:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(Version.self)
            self = .exact(a1)
        case .range:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(CodableRange<Version>.self)
            self = .range(a1.range)
        case .revision:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            self = .revision(a1)
        case .branch:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            self = .branch(a1)
        }
    }
}
