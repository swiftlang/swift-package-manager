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
import Dispatch
import PackageModel

import struct TSCUtility.Version

public protocol PackageSigningEntityStorage {
    /// For a given package, return the signing entities and the package versions that each of them signed.
    @available(*, noasync, message: "Use the async alternative")
    func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<PackageSigners, Error>) -> Void
    )

    /// Record signer for a given package version.
    ///
    /// This throws `PackageSigningEntityStorageError.conflict` if `signingEntity`
    /// of the package version is different from that in storage.
    @available(*, noasync, message: "Use the async alternative")
    func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Add signer for a given package version.
    ///
    /// If the package version already has other `SigningEntity`s in storage, this
    /// API **adds** `signingEntity` to the package version's signers rather than
    /// throwing an error.
    @available(*, noasync, message: "Use the async alternative")
    func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Make `signingEntity` the package's expected signer starting from the given version.
    @available(*, noasync, message: "Use the async alternative")
    func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Make `signingEntity` the only signer for a given package.
    ///
    /// This API deletes all other existing signers from storage, therefore making
    /// `signingEntity` the package's sole signer.
    @available(*, noasync, message: "Use the async alternative")
    func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    )
}

public extension PackageSigningEntityStorage {
    func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws -> PackageSigners {
        try await safe_async {
            self.get(
                package: package,
                observabilityScope: observabilityScope, 
                callbackQueue: callbackQueue,
                callback: $0
            )
        }
    }

    func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.put(
                package: package,
                version: version,
                signingEntity: signingEntity,
                origin: origin,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: $0
            )
        }
    }

    func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.add(
                package: package,
                version: version,
                signingEntity: signingEntity,
                origin: origin,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: $0
            )
        }
    }

    func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.changeSigningEntityFromVersion(
                package: package,
                version: version,
                signingEntity: signingEntity,
                origin: origin,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: $0
            )
        }
    }

    func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.changeSigningEntityForAllVersions(
                package: package,
                version: version,
                signingEntity: signingEntity,
                origin: origin,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                callback: $0
            )
        }
    }
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
    public internal(set) var versions: Set<Version>

    public init(
        signingEntity: SigningEntity,
        origins: Set<SigningEntity.Origin>,
        versions: Set<Version>
    ) {
        self.signingEntity = signingEntity
        self.origins = origins
        self.versions = versions
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

    public func signingEntities(of version: Version) -> Set<SigningEntity> {
        Set(self.signers.values.filter { $0.versions.contains(version) }.map(\.signingEntity))
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
