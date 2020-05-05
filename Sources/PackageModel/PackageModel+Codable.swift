/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic

extension ProductType: Codable {
    private enum CodingKeys: String, CodingKey {
        case library, executable, test
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .library(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .library)
            try unkeyedContainer.encode(a1)
        case .executable:
            try container.encodeNil(forKey: .executable)
        case .test:
            try container.encodeNil(forKey: .test)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .library:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(ProductType.LibraryType.self)
            self = .library(a1)
        case .test:
            self = .test
        case .executable:
            self = .executable
        }
    }
}

extension SystemPackageProviderDescription: Codable {
    private enum CodingKeys: String, CodingKey {
        case brew, apt, yum
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .brew(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .brew)
            try unkeyedContainer.encode(a1)
        case let .apt(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .apt)
            try unkeyedContainer.encode(a1)
        case let .yum(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .yum)
            try unkeyedContainer.encode(a1)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .brew:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode([String].self)
            self = .brew(a1)
        case .apt:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode([String].self)
            self = .apt(a1)
        case .yum:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode([String].self)
            self = .yum(a1)
        }
    }
}

extension PackageDependencyDescription.Requirement: Codable {
    private enum CodingKeys: String, CodingKey {
        case exact, range, revision, branch, localPackage
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
        case .localPackage:
            try container.encodeNil(forKey: .localPackage)
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
        case .localPackage:
            self = .localPackage
        }
    }
}

extension TargetDescription.Dependency: Codable {
    private enum CodingKeys: String, CodingKey {
        case target, product, byName
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .target(a1, a2):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .target)
            try unkeyedContainer.encode(a1)
            try unkeyedContainer.encode(a2)
        case let .product(a1, a2, a3):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .product)
            try unkeyedContainer.encode(a1)
            try unkeyedContainer.encode(a2)
            try unkeyedContainer.encode(a3)
        case let .byName(a1, a2):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .byName)
            try unkeyedContainer.encode(a1)
            try unkeyedContainer.encode(a2)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .target:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            let a2 = try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            self = .target(name: a1, condition: a2)
        case .product:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            let a2 = try unkeyedValues.decodeIfPresent(String.self)
            let a3 = try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            self = .product(name: a1, package: a2, condition: a3)
        case .byName:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            let a2 = try unkeyedValues.decodeIfPresent(PackageConditionDescription.self)
            self = .byName(name: a1, condition: a2)
        }
    }
}

/// Wrapper for package condition so it can be conformed to Codable.
struct PackageConditionWrapper: Codable {
    var platform: PlatformsCondition?
    var config: ConfigurationCondition?

    var condition: PackageConditionProtocol {
        if let platform = platform {
            return platform
        } else if let config = config {
            return config
        } else {
            fatalError("unreachable")
        }
    }

    init(_ condition: PackageConditionProtocol) {
        switch condition {
        case let platform as PlatformsCondition:
            self.platform = platform
        case let config as ConfigurationCondition:
            self.config = config
        default:
            fatalError("unknown condition \(condition)")
        }
    }
}

extension BinaryTarget.ArtifactSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case remote, local
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remote(let a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .remote)
            try unkeyedContainer.encode(a1)
        case .local:
            try container.encodeNil(forKey: .local)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .remote:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(String.self)
            self = .remote(url: a1)
        case .local:
            self = .local
        }
    }
}
