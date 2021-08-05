/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public struct RegistryConfiguration: Hashable {
    public typealias Scope = String

    public enum Version: Int, Codable {
        case v1 = 1
    }

    public static let version: Version = .v1

    public var defaultRegistry: Registry?
    public var scopedRegistries: [Scope: Registry]

    public init() {
        self.defaultRegistry = nil
        self.scopedRegistries = [:]
    }

    public var isEmpty: Bool {
        return self.defaultRegistry == nil && self.scopedRegistries.isEmpty
    }

    public mutating func merge(_ other: RegistryConfiguration) {
        if let defaultRegistry = other.defaultRegistry {
            self.defaultRegistry = defaultRegistry
        }

        for (scope, registry) in other.scopedRegistries {
            self.scopedRegistries[scope] = registry
        }
    }
    
    public func registry(for scope: Scope) -> Registry? {
        return scopedRegistries[scope] ?? defaultRegistry
    }
}

// MARK: - Codable

extension RegistryConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case registries
        case version
    }

    private struct ScopeCodingKey: CodingKey, Hashable {
        static let `default` = ScopeCodingKey(stringValue: "[default]")

        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(Version.RawValue.self, forKey: .version)
        switch Version(rawValue: version) {
        case .v1:
            let nestedContainer = try container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

            self.defaultRegistry = try nestedContainer.decodeIfPresent(Registry.self, forKey: .default)

            var scopedRegistries: [Scope: Registry] = [:]
            for key in nestedContainer.allKeys where key != .default {
                scopedRegistries[key.stringValue] = try nestedContainer.decode(Registry.self, forKey: key)
            }
            self.scopedRegistries = scopedRegistries
        case nil:
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "invalid version: \(version)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Self.version, forKey: .version)

        var nestedContainer = container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

        try nestedContainer.encodeIfPresent(defaultRegistry, forKey: .default)

        for (scope, registry) in scopedRegistries {
            let key = ScopeCodingKey(stringValue: scope)
            try nestedContainer.encode(registry, forKey: key)
        }
    }
}
