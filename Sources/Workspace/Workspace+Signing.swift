//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import enum PackageFingerprint.FingerprintCheckingMode
import struct PackageGraph.ModulesGraph
import struct PackageModel.PackageIdentity
import struct PackageModel.RegistryReleaseMetadata
import enum PackageSigning.SigningEntityCheckingMode

extension FingerprintCheckingMode {
    static func map(_ checkingMode: WorkspaceConfiguration.CheckingMode) -> FingerprintCheckingMode {
        switch checkingMode {
        case .strict:
            return .strict
        case .warn:
            return .warn
        }
    }
}

extension SigningEntityCheckingMode {
    static func map(_ checkingMode: WorkspaceConfiguration.CheckingMode) -> SigningEntityCheckingMode {
        switch checkingMode {
        case .strict:
            return .strict
        case .warn:
            return .warn
        }
    }
}

// MARK: - Signatures

extension Workspace {
    func validateSignatures(
        packageGraph: ModulesGraph,
        expectedSigningEntities: [PackageIdentity: RegistryReleaseMetadata.SigningEntity]
    ) throws {
        try expectedSigningEntities.forEach { identity, expectedSigningEntity in
            if let package = packageGraph.package(for: identity) {
                guard let actualSigningEntity = package.registryMetadata?.signature?.signedBy else {
                    throw SigningError.unsigned(package: identity, expected: expectedSigningEntity)
                }
                if actualSigningEntity != expectedSigningEntity {
                    throw SigningError.mismatchedSigningEntity(
                        package: identity,
                        expected: expectedSigningEntity,
                        actual: actualSigningEntity
                    )
                }
            } else {
                guard let mirror = self.mirrors.mirror(for: identity.description) else {
                    throw SigningError.expectedIdentityNotFound(package: identity)
                }
                let mirroredIdentity = PackageIdentity.plain(mirror)
                guard mirroredIdentity.isRegistry else {
                    throw SigningError.expectedSignedMirroredToSourceControl(
                        package: identity,
                        expected: expectedSigningEntity
                    )
                }
                guard let package = packageGraph.package(for: mirroredIdentity) else {
                    // Unsure if this case is reachable in practice.
                    throw SigningError.expectedIdentityNotFound(package: identity)
                }
                guard let actualSigningEntity = package.registryMetadata?.signature?.signedBy else {
                    throw SigningError.unsigned(package: identity, expected: expectedSigningEntity)
                }
                if actualSigningEntity != expectedSigningEntity {
                    throw SigningError.mismatchedSigningEntity(
                        package: identity,
                        expected: expectedSigningEntity,
                        actual: actualSigningEntity
                    )
                }
            }
        }
    }

    public enum SigningError: Swift.Error {
        case expectedIdentityNotFound(package: PackageIdentity)
        case expectedSignedMirroredToSourceControl(
            package: PackageIdentity,
            expected: RegistryReleaseMetadata.SigningEntity
        )
        case mismatchedSigningEntity(
            package: PackageIdentity,
            expected: RegistryReleaseMetadata.SigningEntity,
            actual: RegistryReleaseMetadata.SigningEntity
        )
        case unsigned(package: PackageIdentity, expected: RegistryReleaseMetadata.SigningEntity)
    }
}
