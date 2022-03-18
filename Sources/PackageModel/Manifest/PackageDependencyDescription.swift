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

import Foundation
import TSCBasic

/// Represents a package dependency.
public enum PackageDependency: Equatable, Hashable {
    case fileSystem(FileSystem)
    case sourceControl(SourceControl)
    case registry(Registry)
    
    public struct FileSystem: Equatable, Hashable, Encodable {
        public let identity: PackageIdentity
        public let nameForTargetDependencyResolutionOnly: String?
        public let path: AbsolutePath
        public let productFilter: ProductFilter
    }

    public struct SourceControl: Equatable, Hashable, Encodable {
        public let identity: PackageIdentity
        public let nameForTargetDependencyResolutionOnly: String?
        public let location: Location
        public let requirement: Requirement
        public let productFilter: ProductFilter

        public enum Requirement: Equatable, Hashable {
            case exact(Version)
            case range(Range<Version>)
            case revision(String)
            case branch(String)
        }

        public enum Location: Equatable, Hashable {
            case local(AbsolutePath)
            case remote(URL)
        }
    }

    public struct Registry: Equatable, Hashable, Encodable {
        public let identity: PackageIdentity
        public let requirement: Requirement
        public let productFilter: ProductFilter

        /// The dependency requirement.
        public enum Requirement: Equatable, Hashable {
            case exact(Version)
            case range(Range<Version>)
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
            return settings.nameForTargetDependencyResolutionOnly ?? PackageIdentityParser.computeDefaultName(fromPath: settings.path)
        case .sourceControl(let settings):
            switch settings.location {
            case .local(let path):
                return settings.nameForTargetDependencyResolutionOnly ?? PackageIdentityParser.computeDefaultName(fromPath: path)
            case .remote(let url):
                return settings.nameForTargetDependencyResolutionOnly ?? PackageIdentityParser.computeDefaultName(fromURL: url)
            }
        case .registry:
            return self.identity.description
        }
    }

    // FIXME: we should simplify target based dependencies such that this is no longer required
    // A name to be used *only* for target dependencies resolution
    public var explicitNameForTargetDependencyResolutionOnly: String? {
        switch self {
        case .fileSystem(let settings):
            return settings.nameForTargetDependencyResolutionOnly
        case .sourceControl(let settings):
            return settings.nameForTargetDependencyResolutionOnly
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

    public func filtered(by productFilter: ProductFilter) -> Self {
        switch self {
        case .fileSystem(let settings):
            return .fileSystem(
                identity: settings.identity,
                nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly,
                path: settings.path,
                productFilter: productFilter
            )
        case .sourceControl(let settings):
            return .sourceControl(
                identity: settings.identity,
                nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly,
                location: settings.location,
                requirement: settings.requirement,
                productFilter: productFilter
            )
        case .registry(let settings):
            return .registry(
                identity: settings.identity,
                requirement: settings.requirement,
                productFilter: productFilter
            )
        }
    }

    public static func fileSystem(identity: PackageIdentity,
                                  nameForTargetDependencyResolutionOnly: String?,
                                  path: AbsolutePath,
                                  productFilter: ProductFilter
    ) -> Self {
        .fileSystem(
            .init(
                identity: identity,
                nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
                path: path,
                productFilter: productFilter
            )
        )
    }

    public static func localSourceControl(identity: PackageIdentity,
                                          nameForTargetDependencyResolutionOnly: String?,
                                          path: AbsolutePath,
                                          requirement: SourceControl.Requirement,
                                          productFilter: ProductFilter
    ) -> Self {
        .sourceControl(
            identity: identity,
            nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
            location: .local(path),
            requirement: requirement,
            productFilter: productFilter
        )
    }
    
    public static func remoteSourceControl(identity: PackageIdentity,
                                           nameForTargetDependencyResolutionOnly: String?,
                                           url: URL,
                                           requirement: SourceControl.Requirement,
                                           productFilter: ProductFilter
    ) -> Self {
        .sourceControl(
            identity: identity,
            nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
            location: .remote(url),
            requirement: requirement,
            productFilter: productFilter
        )
    }

    public static func sourceControl(identity: PackageIdentity,
                                     nameForTargetDependencyResolutionOnly: String?,
                                     location: SourceControl.Location,
                                     requirement: SourceControl.Requirement,
                                     productFilter: ProductFilter
    ) -> Self {
        .sourceControl(
            .init(
                identity: identity,
                nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
                location: location,
                requirement: requirement,
                productFilter: productFilter
            )
        )
    }

    public static func registry(identity: PackageIdentity,
                                requirement: Registry.Requirement,
                                productFilter: ProductFilter
    ) -> Self {
        .registry(
            .init(
                identity: identity,
                requirement: requirement,
                productFilter: productFilter
            )
        )
    }
}

extension Range {
    public static func upToNextMajor(from version: Version) -> Range<Bound> where Bound == Version {
        return version ..< Version(version.major + 1, 0, 0)
    }

    public static func upToNextMinor(from version: Version) -> Range<Bound> where Bound == Version {
        return version ..< Version(version.major, version.minor + 1, 0)
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

extension PackageDependency.SourceControl.Requirement: CustomStringConvertible {
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

extension PackageDependency.Registry.Requirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exact(let version):
            return version.description
        case .range(let range):
            return range.description
        }
    }
}

extension PackageDependency: Encodable {
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
}

extension PackageDependency.SourceControl.Requirement: Encodable {
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
}

extension PackageDependency.SourceControl.Location: Encodable {
    private enum CodingKeys: String, CodingKey {
        case local, remote
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let path):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .local)
            try unkeyedContainer.encode(path)
        case .remote(let url):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .remote)
            try unkeyedContainer.encode(url)
        }
    }
}

extension PackageDependency.Registry.Requirement: Encodable {
    private enum CodingKeys: String, CodingKey {
        case exact, range
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
        }
    }
}
