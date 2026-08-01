//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

import Basics
import _Concurrency
import Dispatch
import PackageModel

import struct TSCUtility.Version

public protocol PackageSigningEntityStorage {
    /// For a given package, return the signing entities and the package versions that each of them signed.
    func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope
    ) throws -> PackageSigners

    /// Record signer for a given package version.
    ///
    /// This throws `PackageSigningEntityStorageError.conflict` if `signingEntity`
    /// of the package version is different from that in storage.
    func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws

    /// Add signer for a given package version.
    ///
    /// If the package version already has other `SigningEntity`s in storage, this
    /// API **adds** `signingEntity` to the package version's signers rather than
    /// throwing an error.
    func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws

    /// Make `signingEntity` the package's expected signer starting from the given version.
    func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws

    /// Make `signingEntity` the only signer for a given package.
    ///
    /// This API deletes all other existing signers from storage, therefore making
    /// `signingEntity` the package's sole signer.
    func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope
    ) throws
}

// MARK: - Models

extension SigningEntity {
    public enum Origin: Hashable, Codable, CustomStringConvertible {
        case registry(URL)

        public var url: URL {
            switch self {
            case .registry(let url):
                return url
            }
        }

        public var description: String {
            switch self {
            case .registry(let url):
                return "registry(\(url))"
            }
        }
    }
}

public struct PackageSigner: Codable {
    public let signingEntity: SigningEntity
    public internal(set) var origins: Set<SigningEntity.Origin>
    private var versionsByIdentifier: [VersionIdentifierKey: Version]

    /// Versions signed by this entity, grouped using semantic-version precedence.
    ///
    /// SwiftPM uses the complete identifier internally when looking up a signer.
    public var versions: Set<Version> {
        Set(self.versionsByIdentifier.values)
    }

    public init(
        signingEntity: SigningEntity,
        origins: Set<SigningEntity.Origin>,
        versions: Set<Version>
    ) {
        self.init(
            signingEntity: signingEntity,
            origins: origins,
            versionIdentifiers: Array(versions)
        )
    }

    /// Creates a signer with versions distinguished by their complete parsed identifiers.
    public init(
        signingEntity: SigningEntity,
        origins: Set<SigningEntity.Origin>,
        versionIdentifiers: [Version]
    ) {
        self.signingEntity = signingEntity
        self.origins = origins
        self.versionsByIdentifier = Dictionary(
            versionIdentifiers.map { (VersionIdentifierKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Versions signed by this entity, distinguished by their complete parsed identifiers.
    public var versionIdentifiers: [Version] {
        self.versionsByIdentifier.values.sorted { lhs, rhs in
            if lhs == rhs {
                return lhs.description < rhs.description
            }
            return lhs < rhs
        }
    }

    package func contains(version: Version) -> Bool {
        self.versionsByIdentifier[VersionIdentifierKey(version)] != nil
    }

    package mutating func add(version: Version) {
        self.versionsByIdentifier[VersionIdentifierKey(version)] = version
    }

    package mutating func add(origin: SigningEntity.Origin) {
        self.origins.insert(origin)
    }

    private enum CodingKeys: CodingKey {
        case signingEntity
        case origins
        case versions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            signingEntity: try container.decode(SigningEntity.self, forKey: .signingEntity),
            origins: try container.decode(Set<SigningEntity.Origin>.self, forKey: .origins),
            versionIdentifiers: try container.decode([Version].self, forKey: .versions)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.signingEntity, forKey: .signingEntity)
        try container.encode(self.origins, forKey: .origins)
        try container.encode(self.versionIdentifiers, forKey: .versions)
    }
}

public struct PackageSigners {
    public internal(set) var expectedSigner: (signingEntity: SigningEntity, fromVersion: Version)?
    public internal(set) var signers: [SigningEntity: PackageSigner]

    public init(
        expectedSigner: (signingEntity: SigningEntity, fromVersion: Version)? = .none,
        signers: [SigningEntity: PackageSigner] = [:]
    ) {
        self.expectedSigner = expectedSigner
        self.signers = signers
    }

    public var isEmpty: Bool {
        self.signers.isEmpty
    }

    public var versionSigningEntities: [Version: Set<SigningEntity>] {
        var versionSigningEntities = [Version: Set<SigningEntity>]()
        for (signingEntity, versions) in self.signers.map({ ($0.key, $0.value.versions) }) {
            versions.forEach { version in
                var signingEntities: Set<SigningEntity> = versionSigningEntities.removeValue(forKey: version) ?? []
                signingEntities.insert(signingEntity)
                versionSigningEntities[version] = signingEntities
            }
        }
        return versionSigningEntities
    }

    package var versionIdentifierSigningEntities: [VersionIdentifierKey: Set<SigningEntity>] {
        var versionSigningEntities = [VersionIdentifierKey: Set<SigningEntity>]()
        for (signingEntity, signer) in self.signers {
            for version in signer.versionIdentifiers {
                versionSigningEntities[VersionIdentifierKey(version), default: []].insert(signingEntity)
            }
        }
        return versionSigningEntities
    }

    public func signingEntities(of version: Version) -> Set<SigningEntity> {
        Set(self.signers.values.filter { $0.contains(version: version) }.map(\.signingEntity))
    }
}

// MARK: - Errors

public enum PackageSigningEntityStorageError: Error, Equatable, CustomStringConvertible {
    case conflict(package: PackageIdentity, version: Version, given: SigningEntity, existing: SigningEntity)
    case unrecognizedSigningEntity(SigningEntity)

    public var description: String {
        switch self {
        case .conflict(let package, let version, let given, let existing):
            return "\(package) version \(version) was previously signed by '\(existing)', which is different from '\(given)'."
        case .unrecognizedSigningEntity(let signingEntity):
            return "'\(signingEntity)' is not recognized and therefore will not be saved."
        }
    }
}

public enum SigningEntityCheckingMode: String {
    case strict
    case warn
}
