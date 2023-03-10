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

import Basics
import Dispatch
import class Foundation.NSLock
import PackageModel
@testable import PackageSigning

import struct TSCUtility.Version

public class MockPackageSigningEntityStorage: PackageSigningEntityStorage {
    private var packageSigners: [PackageIdentity: PackageSigners]
    private let lock = NSLock()

    public init(_ packageSigners: [PackageIdentity: PackageSigners] = [:]) {
        self.packageSigners = packageSigners
    }

    public func get(
        package: PackageIdentity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<PackageSigners, Error>) -> Void
    ) {
        if let packageSigners = self.lock.withLock({ self.packageSigners[package] }) {
            callbackQueue.async {
                callback(.success(packageSigners))
            }
        } else {
            callbackQueue.async {
                callback(.success(.init()))
            }
        }
    }

    public func put(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            try self.lock.withLock {
                var packageSigners: PackageSigners = self.packageSigners[package] ?? .init()

                let otherSigningEntities = packageSigners.signingEntities(of: version).filter { $0 != signingEntity }
                // Error if we try to write a different signing entity for a version
                guard otherSigningEntities.isEmpty else {
                    throw PackageSigningEntityStorageError.conflict(
                        package: package,
                        version: version,
                        given: signingEntity,
                        existing: otherSigningEntities.first! // !-safe because otherSigningEntities is not empty
                    )
                }

                self.add(
                    packageSigners: &packageSigners,
                    signingEntity: signingEntity,
                    origin: origin,
                    version: version
                )

                self.packageSigners[package] = packageSigners
            }

            callbackQueue.async {
                callback(.success(()))
            }
        } catch {
            callbackQueue.async {
                callback(.failure(error))
            }
        }
    }

    public func add(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.lock.withLock {
            var packageSigners: PackageSigners = self.packageSigners[package] ?? .init()
            self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            self.packageSigners[package] = packageSigners
        }
        callback(.success(()))
    }

    public func changeSigningEntityFromVersion(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.lock.withLock {
            var packageSigners: PackageSigners = self.packageSigners[package] ?? .init()
            packageSigners.expectedSigner = (signingEntity: signingEntity, fromVersion: version)
            self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            self.packageSigners[package] = packageSigners
        }
        callback(.success(()))
    }

    public func changeSigningEntityForAllVersions(
        package: PackageIdentity,
        version: Version,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        callback: @escaping (Result<Void, Error>) -> Void
    ) {
        self.lock.withLock {
            var packageSigners: PackageSigners = self.packageSigners[package] ?? .init()
            packageSigners.expectedSigner = (signingEntity: signingEntity, fromVersion: version)
            // Delete all other signers
            packageSigners.signers = packageSigners.signers.filter { $0.key == signingEntity }
            self.add(
                packageSigners: &packageSigners,
                signingEntity: signingEntity,
                origin: origin,
                version: version
            )
            self.packageSigners[package] = packageSigners
        }
        callback(.success(()))
    }

    private func add(
        packageSigners: inout PackageSigners,
        signingEntity: SigningEntity,
        origin: SigningEntity.Origin,
        version: Version
    ) {
        if var existingSigner = packageSigners.signers.removeValue(forKey: signingEntity) {
            existingSigner.origins.insert(origin)
            existingSigner.versions.insert(version)
            packageSigners.signers[signingEntity] = existingSigner
        } else {
            let signer = PackageSigner(
                signingEntity: signingEntity,
                origins: [origin],
                versions: [version]
            )
            packageSigners.signers[signingEntity] = signer
        }
    }
}
