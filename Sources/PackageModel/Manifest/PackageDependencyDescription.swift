/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// Represents a package dependency.
public enum PackageDependency: Equatable {

    public struct FileSystem: Equatable, Codable {
        public let identity: PackageIdentity
        public let name: String?
        public let path: AbsolutePath
        public let productFilter: ProductFilter
    }

    public struct SourceControl: Equatable, Codable {
        public let identity: PackageIdentity
        public let name: String?
        public let location: String
        public let requirement: Requirement
        public let productFilter: ProductFilter
    }

    public struct Registry: Equatable, Codable {
        public let identity: PackageIdentity
        public let requirement: Requirement
        public let productFilter: ProductFilter
    }

    case fileSystem(FileSystem)
    case sourceControl(SourceControl)
    case registry(Registry)

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
        case .fileSystem(let settings):
            return settings.identity
        case .sourceControl(let settings):
            return settings.identity
        case .registry(let settings):
            return settings.identity
        }
    }

    // FIXME: we should simplify target based dependencies such that this is no longer required
    // A name to be used *only* for target dependencies resolution
    public var nameForTargetDependencyResolutionOnly: String {
        switch self {
        case .fileSystem(let settings):
            return settings.name ?? LegacyPackageIdentity.computeDefaultName(fromURL: settings.path.pathString)
        case .sourceControl(let settings):
            return settings.name ?? LegacyPackageIdentity.computeDefaultName(fromURL: settings.location)
        case .registry:
            return self.identity.description
        }
    }

    // FIXME: we should simplify target based dependencies such that this is no longer required
    // A name to be used *only* for target dependencies resolution
    public var explicitNameForTargetDependencyResolutionOnly: String? {
        switch self {
        case .fileSystem(let settings):
            return settings.name
        case .sourceControl(let settings):
            return settings.name
        case .registry:
            return nil
        }
    }

    public var productFilter: ProductFilter {
        switch self {
        case .fileSystem(let settings):
            return settings.productFilter
        case .sourceControl(let settings):
            return settings.productFilter
        case .registry(let settings):
            return settings.productFilter
        }
    }

    public var isLocal: Bool {
        switch self {
        case .fileSystem:
            return true
        case .sourceControl:
            return false
        case .registry:
            return false
        }
    }

    public func filtered(by productFilter: ProductFilter) -> Self {
        switch self {
        case .fileSystem(let settings):
            return .fileSystem(identity: settings.identity,
                               name: settings.name,
                               path: settings.path,
                               productFilter: productFilter)
        case .sourceControl(let settings):
            return .sourceControl(identity: settings.identity,
                                  name: settings.name,
                                  location: settings.location,
                                  requirement: settings.requirement,
                                  productFilter: productFilter)
        case .registry(let settings):
            return .registry(identity: settings.identity,
                             requirement: settings.requirement,
                             productFilter: productFilter)
        }
    }

    public static func fileSystem(identity: PackageIdentity,
                                  name: String?,
                                  path: AbsolutePath,
                                  productFilter: ProductFilter
    ) -> Self {
        .fileSystem (
            .init(identity: identity,
                  name: name,
                  path: path,
                  productFilter: productFilter)
        )
    }

    public static func sourceControl(identity: PackageIdentity,
                                     name: String?,
                                     location: String,
                                     requirement: Requirement,
                                     productFilter: ProductFilter
    ) -> Self {
        .sourceControl (
            .init(identity: identity,
                  name: name,
                  location: location,
                  requirement: requirement,
                  productFilter: productFilter)
        )
    }

    public static func registry(identity: PackageIdentity,
                                requirement: Requirement,
                                productFilter: ProductFilter
    ) -> Self {
        .registry (
            .init(identity: identity,
                  requirement: requirement,
                  productFilter: productFilter)
        )
    }
}

extension PackageDependency: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fileSystem(let data):
            return "fileSystem[\(data)]"
        case .sourceControl(let data):
            return "sourceControl[\(data)]"
        case .registry(let data):
            return "registry[\(data)]"
        }
    }
}

extension PackageDependency.Requirement: CustomStringConvertible {
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

extension PackageDependency: Codable {
    private enum CodingKeys: String, CodingKey {
        case local, fileSystem, scm, sourceControl, registry
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fileSystem(let settings):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .fileSystem)
            try unkeyedContainer.encode(settings)
        case .sourceControl(let settings):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .sourceControl)
            try unkeyedContainer.encode(settings)
        case .registry(let settings):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .registry)
            try unkeyedContainer.encode(settings)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .local, .fileSystem:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let data = try unkeyedValues.decode(FileSystem.self)
            self = .fileSystem(data)
        case .scm, .sourceControl:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let data = try unkeyedValues.decode(SourceControl.self)
            self = .sourceControl(data)
        case .registry:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let data = try unkeyedValues.decode(Registry.self)
            self = .registry(data)
        }
    }
}

extension PackageDependency.Requirement: Codable {
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
