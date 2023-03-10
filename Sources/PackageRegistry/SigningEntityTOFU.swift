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
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signingEntityStorage = self.signingEntityStorage else {
            return completion(.success(()))
        }

        signingEntityStorage.get(
            package: package.underlying,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let signerVersions):
                self.validateSigningEntity(
                    package: package,
                    version: version,
                    signingEntity: signingEntity,
                    signerVersions: signerVersions,
                    observabilityScope: observabilityScope
                ) { validateResult in
                    switch validateResult {
                    case .success(let shouldWrite):
                        // We only use certain type(s) of signing entity for TOFU
                        guard shouldWrite, let signingEntity = signingEntity, signingEntity.isRecognized else {
                            return completion(.success(()))
                        }
                        self.writeToStorage(
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
                observabilityScope.emit(error: "Failed to get signing entity for \(package) from storage: \(error)")
                completion(.failure(error))
            }
        }
    }

    private func validateSigningEntity(
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity?,
        signerVersions: [SigningEntity: Set<Version>],
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        // Package is never signed.
        // If signingEntity is nil, it means package remains unsigned, which is OK. (none -> none)
        // Otherwise, package has gained a signing entity, which is also OK. (none -> some)
        if signerVersions.isEmpty {
            return completion(.success(true))
        }

        // If we get to this point, it means we have seen a signed version of the package.

        // TODO: It's possible that some of the signing entity changes are legitimate:
        // e.g., change of package ownership, package author decides to stop signing releases, etc.
        // Instead of failing, we should allow and prompt user to add/replace/remove signing entity.

        // We recorded the version's signer previously
        if let signerForVersion = signerVersions.signingEntity(of: version) {
            // The given signer is different
            // TODO: This could indicate a legitimate change in package ownership
            guard signerForVersion == signingEntity else {
                return self.handleSigningEntityChanged(
                    package: package,
                    version: version,
                    latest: signingEntity,
                    existing: signerForVersion,
                    observabilityScope: observabilityScope
                ) { result in
                    completion(result.tryMap { false })
                }
            }
            // Signer remains the same for the version
            return completion(.success(false))
        }

        switch signingEntity {
        // Is the package changing from one signer to another?
        case .some(let signingEntity):
            // Check signer(s) of other version(s)
            if let otherSigner = signerVersions.keys.filter({ $0 != signingEntity }).first {
                // There is a different signer
                // TODO: This could indicate a legitimate change in package ownership
                self.handleSigningEntityChanged(
                    package: package,
                    latest: signingEntity,
                    existing: otherSigner,
                    observabilityScope: observabilityScope
                ) { result in
                    completion(result.tryMap { false })
                }
            } else {
                // Package doesn't have any other signer besides the given one, which is good.
                completion(.success(true))
            }
        // Or is the package going from having a signer to .none?
        case .none:
            let versionSigners = signerVersions.versionSigners
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
            let olderSignedVersions = versionSigners.keys.filter { $0.major == version.major && $0 < version }
                .sorted(by: >)
            for signedVersion in olderSignedVersions {
                if let versionSigner = versionSigners[signedVersion] {
                    return self.handleSigningEntityChanged(
                        package: package,
                        latest: signingEntity,
                        existing: versionSigner,
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
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signingEntity: SigningEntity,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let signingEntityStorage = self.signingEntityStorage else {
            return completion(.success(()))
        }

        signingEntityStorage.put(
            package: package.underlying,
            version: version,
            signingEntity: signingEntity,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(PackageSigningEntityStorageError.conflict(_, _, _, let existing)):
                self.handleSigningEntityChanged(
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

    private func handleSigningEntityChanged(
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
                package: package.underlying,
                version: version,
                latest: latest,
                previous: existing
            )))
        case .warn:
            observabilityScope
                .emit(
                    warning: "The signing entity \(String(describing: latest)) for '\(package)@\(version)' does not match previously recorded value \(existing)"
                )
            completion(.success(()))
        }
    }

    private func handleSigningEntityChanged(
        package: PackageIdentity.RegistryIdentity,
        latest: SigningEntity?,
        existing: SigningEntity,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch self.signingEntityCheckingMode {
        case .strict:
            completion(.failure(RegistryError.signingEntityForPackageChanged(
                package: package.underlying,
                latest: latest, previous: existing
            )))
        case .warn:
            observabilityScope
                .emit(
                    warning: "The signing entity \(String(describing: latest)) for '\(package)' does not match previously recorded value \(existing)"
                )
            completion(.success(()))
        }
    }
}
