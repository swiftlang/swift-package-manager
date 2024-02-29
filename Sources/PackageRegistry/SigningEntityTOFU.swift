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

import Dispatch

import Basics
import PackageModel
import PackageSigning

import struct TSCUtility.Version

struct PackageSigningEntityTOFU {
    private let signingEntityStorage: PackageSigningEntityStorage?
    private let signingEntityCheckingMode: SigningEntityCheckingMode

    init(
        signingEntityStorage: PackageSigningEntityStorage?,
        signingEntityCheckingMode: SigningEntityCheckingMode
    ) {
        self.signingEntityStorage = signingEntityStorage
        self.signingEntityCheckingMode = signingEntityCheckingMode
    }
    
    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws {
        try await safe_async {
            self.validate(
                registry: registry,
                package: package,
                version: version,
                signingEntity: signingEntity,
                observabilityScope: observabilityScope,
                callbackQueue: callbackQueue,
                completion: $0
            )
        }
    }

    @available(*, noasync, message: "Use the async alternative")
    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signingEntityStorage else {
            return completion(.success(()))
        }

        signingEntityStorage.get(
            package: package.underlying,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let packageSigners):
                self.validateSigningEntity(
                    registry: registry,
                    package: package,
                    version: version,
                    signingEntity: signingEntity,
                    packageSigners: packageSigners,
                    observabilityScope: observabilityScope
                ) { validateResult in
                    switch validateResult {
                    case .success(let shouldWrite):
                        // We only use certain type(s) of signing entity for TOFU
                        guard shouldWrite, let signingEntity = signingEntity, case .recognized = signingEntity else {
                            return completion(.success(()))
                        }
                        self.writeToStorage(
                            registry: registry,
                            package: package,
                            version: version,
                            signingEntity: signingEntity,
                            observabilityScope: observabilityScope,
                            callbackQueue: callbackQueue,
                            completion: completion
                        )
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                observabilityScope.emit(
                    error: "Failed to get signing entity for \(package) from storage",
                    underlyingError: error
                )
                completion(.failure(error))
            }
        }
    }

    private func validateSigningEntity(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        packageSigners: PackageSigners,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        // Package is never signed.
        // If signingEntity is nil, it means package remains unsigned, which is OK. (none -> none)
        // Otherwise, package has gained a signer, which is also OK. (none -> some)
        if packageSigners.isEmpty {
            return completion(.success(true))
        }

        // If we get to this point, it means we have seen a signed version of the package.

        let signingEntitiesForVersion = packageSigners.signingEntities(of: version)
        // We recorded the version's signer(s) previously
        if !signingEntitiesForVersion.isEmpty {
            guard let signingEntityToCheck = signingEntity,
                  signingEntitiesForVersion.contains(signingEntityToCheck)
            else {
                // The given signer is nil or different
                // TODO: This could indicate a legitimate change
                //   - If signingEntity is nil, it could mean the package author has stopped signing the package.
                //   - If signingEntity is non-nil, it could mean the package has changed ownership and the new owner
                //     is re-signing all of the package versions.
                return self.handleSigningEntityForPackageVersionChanged(
                    registry: registry,
                    package: package,
                    version: version,
                    latest: signingEntity,
                    existing: signingEntitiesForVersion.first!, // !-safe since signingEntitiesForVersion is non-empty
                    observabilityScope: observabilityScope
                ) { result in
                    completion(result.tryMap { false })
                }
            }
            // Signer remains the same for the version
            return completion(.success(false))
        }

        // Check signer(s) of other version(s)
        switch signingEntity {
        // Is the package changing from one signer to another?
        case .some(let signingEntity):
            // Does the package have an expected signer?
            if let expectedSigner = packageSigners.expectedSigner,
               version >= expectedSigner.fromVersion
            {
                // Signer is as expected
                if signingEntity == expectedSigner.signingEntity {
                    return completion(.success(true))
                }
                // If the signer is different from expected but has been seen before,
                // we allow versions before its highest known version to be signed
                // by this signer. This is to handle the case where a signer was recorded
                // before expectedSigner is set, and it had signed a version newer than
                // expectedSigner.fromVersion. For example, if signer A is recorded to have
                // signed v2.0 and later expectedSigner is set to signer B with fromVersion
                // set to v1.5, then it should not be a TOFU failure if we see signer A
                // for v1.9.
                if let knownSigner = packageSigners.signers[signingEntity],
                   let highestKnownVersion = knownSigner.versions.sorted(by: >).first,
                   version < highestKnownVersion
                {
                    return completion(.success(true))
                }
                // Different signer than expected
                self.handleSigningEntityForPackageChanged(
                    registry: registry,
                    package: package,
                    version: version,
                    latest: signingEntity,
                    existing: expectedSigner.signingEntity,
                    existingVersion: expectedSigner.fromVersion,
                    observabilityScope: observabilityScope
                ) { result in
                    completion(result.tryMap { false })
                }
            } else {
                // There might be other signers, but if we have seen this signer before, allow it.
                if packageSigners.signers[signingEntity] != nil {
                    return completion(.success(true))
                }

                let otherSigningEntities = packageSigners.signers.keys.filter { $0 != signingEntity }
                for otherSigningEntity in otherSigningEntities {
                    // We have not seen this signer before, and there is at least one other signer already.
                    // TODO: This could indicate a legitimate change in package ownership
                    if let existingVersion = packageSigners.signers[otherSigningEntity]?.versions.sorted(by: >).first {
                        return self.handleSigningEntityForPackageChanged(
                            registry: registry,
                            package: package,
                            version: version,
                            latest: signingEntity,
                            existing: otherSigningEntity,
                            existingVersion: existingVersion,
                            observabilityScope: observabilityScope
                        ) { result in
                            completion(result.tryMap { false })
                        }
                    }
                }

                // Package doesn't have any other signer besides the given one, which is good.
                completion(.success(true))
            }
        // Or is the package going from having a signer to .none?
        case .none:
            let versionSigningEntities = packageSigners.versionSigningEntities
            // If the given version is semantically newer than any signed version,
            // then it must be signed. (i.e., when a package starts being signed
            // at a version, then all future versions must be signed.)
            // TODO: We might want to allow package becoming unsigned
            //
            // Here we try to handle the scenario where there is more than
            // one major version branch, and signing didn't start from the beginning
            // for both of them. For example, suppose a project has 1.x and 2.x active
            // major versions, and signing starts at 1.2.0 and 2.2.0. The first version
            // that SwiftPM downloads is 1.5.0, which is signed and signer gets recorded.
            //   - When unsigned v1.1.0 is downloaded, we don't fail because it's
            //     an older version (i.e., < 1.5.0) and we allow it to be unsigned.
            //   - When unsigned v1.6.0 is downloaded, we fail because it's
            //     a newer version (i.e., < 1.5.0) and we assume it to be signed.
            //   - When unsigned v2.0.0 is downloaded, we don't fail because we haven't
            //     seen a signed 2.x release yet, so we assume 2.x releases are not signed.
            //     (this might be controversial)
            let olderSignedVersions = versionSigningEntities.keys
                .filter { $0.major == version.major && $0 < version }
                .sorted(by: >)
            for olderSignedVersion in olderSignedVersions {
                if let olderVersionSigner = versionSigningEntities[olderSignedVersion]?.first {
                    return self.handleSigningEntityForPackageChanged(
                        registry: registry,
                        package: package,
                        version: version,
                        latest: signingEntity,
                        existing: olderVersionSigner,
                        existingVersion: olderSignedVersion,
                        observabilityScope: observabilityScope
                    ) { result in
                        completion(result.tryMap { false })
                    }
                }
            }
            // Assume the given version is an older version before package started getting signed
            completion(.success(false))
        }
    }

    private func writeToStorage(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signingEntityStorage else {
            return completion(.success(()))
        }

        signingEntityStorage.put(
            package: package.underlying,
            version: version,
            signingEntity: signingEntity,
            origin: .registry(registry.url),
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(PackageSigningEntityStorageError.conflict(_, _, _, let existing)):
                self.handleSigningEntityForPackageVersionChanged(
                    registry: registry,
                    package: package,
                    version: version,
                    latest: signingEntity,
                    existing: existing,
                    observabilityScope: observabilityScope,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func handleSigningEntityForPackageVersionChanged(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        latest: SigningEntity?,
        existing: SigningEntity,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch self.signingEntityCheckingMode {
        case .strict:
            completion(.failure(RegistryError.signingEntityForReleaseChanged(
                registry: registry,
                package: package.underlying,
                version: version,
                latest: latest,
                previous: existing
            )))
        case .warn:
            observabilityScope
                .emit(
                    warning: "the signing entity '\(String(describing: latest))' from \(registry) for \(package) version \(version) is different from the previously recorded value '\(existing)'"
                )
            completion(.success(()))
        }
    }

    private func handleSigningEntityForPackageChanged(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        latest: SigningEntity?,
        existing: SigningEntity,
        existingVersion: Version,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch self.signingEntityCheckingMode {
        case .strict:
            completion(.failure(RegistryError.signingEntityForPackageChanged(
                registry: registry,
                package: package.underlying,
                version: version,
                latest: latest,
                previous: existing,
                previousVersion: existingVersion
            )))
        case .warn:
            observabilityScope
                .emit(
                    warning: "the signing entity '\(String(describing: latest))' from \(registry) for \(package) version \(version) is different from the previously recorded value '\(existing)' for version \(existingVersion)"
                )
            completion(.success(()))
        }
    }
}
