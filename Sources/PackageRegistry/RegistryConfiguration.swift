//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
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
    static func authenticationStorageKey(for registryURL: URL) throws -> String {
        guard let host = registryURL.host?.lowercased() else {
            throw RegistryError.invalidURL(registryURL)
        }

        return [host, registryURL.port?.description].compactMap { $0 }.joined(separator: ":")
    }

    public enum Version: Int, Codable {
        case v1 = 1
    }

    public static let version: Version = .v1

    public var defaultRegistry: Registry?
    public var scopedRegistries: [PackageIdentity.Scope: Registry]
    public var registryAuthentication: [String: Authentication]
    public var security: Security?

    public init() {
        self.defaultRegistry = .none
        self.scopedRegistries = [:]
        self.registryAuthentication = [:]
        self.security = .none
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

    public func registry(for package: PackageIdentity) -> Registry? {
        guard let registryIdentity = package.registry else {
            return .none
        }
        return self.registry(for: registryIdentity.scope)
    }

    public func registry(for scope: PackageIdentity.Scope) -> Registry? {
        self.scopedRegistries[scope] ?? self.defaultRegistry
    }

    public var explicitlyConfigured: Bool {
        self.defaultRegistry != nil || !self.scopedRegistries.isEmpty
    }

    public func authentication(for registryURL: URL) throws -> Authentication? {
        let key = try Self.authenticationStorageKey(for: registryURL)
        return self.registryAuthentication[key]
    }

    public mutating func add(authentication: Authentication, for registryURL: URL) throws {
        let key = try Self.authenticationStorageKey(for: registryURL)
        self.registryAuthentication[key] = authentication
    }

    public mutating func removeAuthentication(for registryURL: URL) {
        guard let key = try? Self.authenticationStorageKey(for: registryURL) else { return }
        self.registryAuthentication.removeValue(forKey: key)
    }

    public func signing(for package: PackageIdentity.RegistryIdentity, registry: Registry) -> Security.Signing {
        let global = self.security?.default.signing
        let registryOverrides = registry.url.host.flatMap { host in self.security?.registryOverrides[host]?.signing }
        let scopeOverrides = self.security?.scopeOverrides[package.scope]?.signing
        let packageOverrides = self.security?.packageOverrides[package]?.signing

        var signing = Security.Signing.default
        if let global {
            signing.merge(global)
        }
        if let registryOverrides {
            signing.merge(registryOverrides)
        }
        if let scopeOverrides {
            signing.merge(scopeOverrides)
        }
        if let packageOverrides {
            signing.merge(packageOverrides)
        }

        return signing
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
    public struct Security: Hashable {
        public var `default`: Global
        public var registryOverrides: [String: RegistryOverride]
        public var scopeOverrides: [PackageIdentity.Scope: ScopePackageOverride]
        public var packageOverrides: [PackageIdentity.RegistryIdentity: ScopePackageOverride]

        public init() {
            self.default = Global()
            self.registryOverrides = [:]
            self.scopeOverrides = [:]
            self.packageOverrides = [:]
        }

        // for testing
        init(
            default: Global,
            registryOverrides: [String: RegistryOverride] = [:],
            scopeOverrides: [PackageIdentity.Scope: ScopePackageOverride] = [:],
            packageOverrides: [PackageIdentity.RegistryIdentity: ScopePackageOverride] = [:]
        ) {
            self.default = `default`
            self.registryOverrides = registryOverrides
            self.scopeOverrides = scopeOverrides
            self.packageOverrides = packageOverrides
        }

        public struct Global: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }

            // for testing
            init(signing: Signing) {
                self.signing = signing
            }
        }

        public struct RegistryOverride: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }
        }

        public struct Signing: Hashable, Codable {
            static let `default`: Signing = {
                var signing = Signing()
                signing.onUnsigned = .warn
                signing.onUntrustedCertificate = .warn
                signing.trustedRootCertificatesPath = nil
                signing.includeDefaultTrustedRootCertificates = true

                var validationChecks = Signing.ValidationChecks()
                validationChecks.certificateExpiration = .disabled
                validationChecks.certificateRevocation = .disabled
                signing.validationChecks = validationChecks

                return signing
            }()

            public var onUnsigned: OnUnsignedAction?
            public var onUntrustedCertificate: OnUntrustedCertificateAction?
            public var trustedRootCertificatesPath: String?
            public var includeDefaultTrustedRootCertificates: Bool?
            public var validationChecks: ValidationChecks?

            public init() {
                self.onUnsigned = nil
                self.onUntrustedCertificate = nil
                self.trustedRootCertificatesPath = nil
                self.includeDefaultTrustedRootCertificates = nil
                self.validationChecks = nil
            }

            mutating func merge(_ other: Signing) {
                if let onUnsigned = other.onUnsigned {
                    self.onUnsigned = onUnsigned
                }
                if let onUntrustedCertificate = other.onUntrustedCertificate {
                    self.onUntrustedCertificate = onUntrustedCertificate
                }
                if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                    self.trustedRootCertificatesPath = trustedRootCertificatesPath
                }
                if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                    self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                }
                if let validationChecks = other.validationChecks {
                    self.validationChecks?.merge(validationChecks)
                }
            }

            mutating func merge(_ other: ScopePackageOverride.Signing) {
                if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                    self.trustedRootCertificatesPath = trustedRootCertificatesPath
                }
                if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                    self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                }
            }

            public enum OnUnsignedAction: String, Hashable, Codable {
                case prompt
                case error
                case warn
                case silentAllow
            }

            public enum OnUntrustedCertificateAction: String, Hashable, Codable {
                case prompt
                case error
                case warn
                case silentAllow
            }

            public struct ValidationChecks: Hashable, Codable {
                public var certificateExpiration: CertificateExpirationCheck?
                public var certificateRevocation: CertificateRevocationCheck?

                public init() {
                    self.certificateExpiration = nil
                    self.certificateRevocation = nil
                }

                mutating func merge(_ other: ValidationChecks) {
                    if let certificateExpiration = other.certificateExpiration {
                        self.certificateExpiration = certificateExpiration
                    }
                    if let certificateRevocation = other.certificateRevocation {
                        self.certificateRevocation = certificateRevocation
                    }
                }

                public enum CertificateExpirationCheck: String, Hashable, Codable {
                    case enabled
                    case disabled
                }

                public enum CertificateRevocationCheck: String, Hashable, Codable {
                    case strict
                    case allowSoftFail
                    case disabled
                }
            }
        }

        public struct ScopePackageOverride: Hashable, Codable {
            public var signing: Signing?

            public init() {
                self.signing = nil
            }

            public struct Signing: Hashable, Codable {
                public var trustedRootCertificatesPath: String?
                public var includeDefaultTrustedRootCertificates: Bool?

                public init() {
                    self.trustedRootCertificatesPath = nil
                    self.includeDefaultTrustedRootCertificates = nil
                }

                mutating func merge(_ other: Signing) {
                    if let trustedRootCertificatesPath = other.trustedRootCertificatesPath {
                        self.trustedRootCertificatesPath = trustedRootCertificatesPath
                    }
                    if let includeDefaultTrustedRootCertificates = other.includeDefaultTrustedRootCertificates {
                        self.includeDefaultTrustedRootCertificates = includeDefaultTrustedRootCertificates
                    }
                }
            }
        }
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

    fileprivate struct ScopeCodingKey: CodingKey, Hashable {
        static let `default` = ScopeCodingKey(stringValue: "[default]")

        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    fileprivate struct PackageCodingKey: CodingKey, Hashable {
        var stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
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

            self.registryAuthentication = try container.decodeIfPresent(
                [String: Authentication].self,
                forKey: .authentication
            ) ?? [:]
            self.security = try container.decodeIfPresent(Security.self, forKey: .security) ?? nil
        case nil:
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "invalid version: \(version)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Self.version, forKey: .version)

        var registriesContainer = container.nestedContainer(keyedBy: ScopeCodingKey.self, forKey: .registries)

        try registriesContainer.encodeIfPresent(self.defaultRegistry, forKey: .default)

        for (scope, registry) in self.scopedRegistries {
            let key = ScopeCodingKey(stringValue: scope.description)
            try registriesContainer.encode(registry, forKey: key)
        }

        try container.encode(self.registryAuthentication, forKey: .authentication)
        try container.encodeIfPresent(self.security, forKey: .security)
    }
}

extension PackageModel.Registry: Codable {
    private enum CodingKeys: String, CodingKey {
        case url
        case supportsAvailability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            url: container.decode(URL.self, forKey: .url),
            supportsAvailability: container.decodeIfPresent(Bool.self, forKey: .supportsAvailability) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.url, forKey: .url)
        try container.encode(self.supportsAvailability, forKey: .supportsAvailability)
    }
}

extension RegistryConfiguration.Security: Codable {
    private enum CodingKeys: String, CodingKey {
        case `default`
        case registryOverrides
        case scopeOverrides
        case packageOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.default = try container.decodeIfPresent(Global.self, forKey: .default) ?? Global()
        self.registryOverrides = try container.decodeIfPresent(
            [String: RegistryOverride].self,
            forKey: .registryOverrides
        ) ?? [:]

        let scopeOverridesContainer = try container.decodeIfPresent(
            [String: ScopePackageOverride].self,
            forKey: .scopeOverrides
        ) ?? [:]
        var scopeOverrides: [PackageIdentity.Scope: ScopePackageOverride] = [:]
        for (key, scopeOverride) in scopeOverridesContainer {
            let scope = try PackageIdentity.Scope(validating: key)
            scopeOverrides[scope] = scopeOverride
        }
        self.scopeOverrides = scopeOverrides

        let packageOverridesContainer = try container.decodeIfPresent(
            [String: ScopePackageOverride].self,
            forKey: .packageOverrides
        ) ?? [:]
        var packageOverrides: [PackageIdentity.RegistryIdentity: ScopePackageOverride] = [:]
        for (key, packageOverride) in packageOverridesContainer {
            guard let packageIdentity = PackageIdentity.plain(key).registry else {
                throw DecodingError.dataCorruptedError(
                    forKey: .packageOverrides,
                    in: container,
                    debugDescription: "invalid package identifier: '\(key)'"
                )
            }
            packageOverrides[packageIdentity] = packageOverride
        }
        self.packageOverrides = packageOverrides
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.default, forKey: .default)
        try container.encode(self.registryOverrides, forKey: .registryOverrides)

        var scopeOverridesContainer = container.nestedContainer(
            keyedBy: RegistryConfiguration.ScopeCodingKey.self,
            forKey: .scopeOverrides
        )
        for (scope, scopeOverride) in self.scopeOverrides {
            let key = RegistryConfiguration.ScopeCodingKey(stringValue: scope.description)
            try scopeOverridesContainer.encode(scopeOverride, forKey: key)
        }

        var packageOverridesContainer = container.nestedContainer(
            keyedBy: RegistryConfiguration.PackageCodingKey.self,
            forKey: .packageOverrides
        )
        for (packageIdentity, packageOverride) in self.packageOverrides {
            let key = RegistryConfiguration.PackageCodingKey(stringValue: packageIdentity.description)
            try packageOverridesContainer.encode(packageOverride, forKey: key)
        }
    }
}
