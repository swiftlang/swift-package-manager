//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel

public struct RegistryConfiguration: Hashable {
    public enum Version: Int, Codable {
        case v1 = 1
    }

    public static let version: Version = .v1

    public var defaultRegistry: Registry?
    public var scopedRegistries: [PackageIdentity.Scope: Registry]
    public var registryAuthentication: [String: Authentication]
    public var security: Security?

    public init() {
        self.defaultRegistry = nil
        self.scopedRegistries = [:]
        self.registryAuthentication = [:]
        self.security = nil
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

        for (registry, authentication) in other.registryAuthentication {
            self.registryAuthentication[registry] = authentication
        }
        
        if let security = other.security {
            self.security = security
        }
    }

    public func registry(for scope: PackageIdentity.Scope) -> Registry? {
        self.scopedRegistries[scope] ?? self.defaultRegistry
    }

    public func authentication(for registryURL: URL) -> Authentication? {
        guard let host = registryURL.host else { return nil }
        return self.registryAuthentication[host]
    }
}

extension RegistryConfiguration {
    public struct Authentication: Hashable, Codable {
        public var type: AuthenticationType
        public var loginAPIPath: String?
        
        public init(type: AuthenticationType, loginAPIPath: String? = nil) {
            self.type = type
            self.loginAPIPath = loginAPIPath
        }
    }

    public enum AuthenticationType: String, Hashable, Codable {
        case basic
        case token
    }
}

extension RegistryConfiguration {
    public struct Security: Hashable, Codable {
        public var credentialStore: CredentialStore
        
        private enum CodingKeys: String, CodingKey {
            case credentialStore
        }
        
        public init(credentialStore: CredentialStore = .default) {
            self.credentialStore = credentialStore
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.credentialStore = try container.decodeIfPresent(CredentialStore.self, forKey: .credentialStore) ?? .default
        }
    }

    public enum CredentialStore: String, Hashable, Codable {
        case `default`
        case netrc
    }
}

// MARK: - Codable

extension RegistryConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case registries
        case authentication
        case security
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

    private struct AuthenticationCodingKey: CodingKey, Hashable {
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

            var scopedRegistries: [PackageIdentity.Scope: Registry] = [:]
            for key in nestedContainer.allKeys where key != .default {
                let scope = try PackageIdentity.Scope(validating: key.stringValue)
                scopedRegistries[scope] = try nestedContainer.decode(Registry.self, forKey: key)
            }
            self.scopedRegistries = scopedRegistries

            self.registryAuthentication = try container.decodeIfPresent([String: Authentication].self, forKey: .authentication) ?? [:]
            self.security = try container.decodeIfPresent(Security.self, forKey: .security)
        case nil:
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "invalid version: \(version)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Self.version, forKey: .version)

        var registriesContainer = container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

        try registriesContainer.encodeIfPresent(self.defaultRegistry, forKey: .default)

        for (scope, registry) in scopedRegistries {
            let key = ScopeCodingKey(stringValue: scope.description)
            try registriesContainer.encode(registry, forKey: key)
        }

        try container.encode(self.registryAuthentication, forKey: .authentication)
        try container.encode(self.security, forKey: .security)
    }
}
