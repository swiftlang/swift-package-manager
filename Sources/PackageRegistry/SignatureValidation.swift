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

#if swift(>=5.5.2)
import _Concurrency
#endif

import Dispatch
import struct Foundation.Data

import Basics
import PackageModel
import PackageSigning

import struct TSCUtility.Version

struct SignatureValidation {
    private let signingEntityTOFU: PackageSigningEntityTOFU
    private let registryClient: RegistryClient

    init(
        signingEntityStorage: PackageSigningEntityStorage?,
        signingEntityCheckingMode: SigningEntityCheckingMode,
        registryClient: RegistryClient
    ) {
        self.signingEntityTOFU = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )
        self.registryClient = registryClient
    }

    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.getAndValidateSignature(
            registry: registry,
            package: package,
            version: version,
            content: content,
            configuration: configuration,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            completion(
                result.tryMap { signingEntity in
                    // Always do signing entity TOFU check at the end,
                    // whether the package is signed or not.
                    self.signingEntityTOFU.validate(
                        package: package,
                        version: version,
                        signingEntity: signingEntity,
                        observabilityScope: observabilityScope,
                        callbackQueue: callbackQueue,
                        completion: completion
                    )
                }
            )
        }
    }

    private func getAndValidateSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        self.getSourceArchiveSignature(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let signature):
                self.validateSignature(
                    registry: registry,
                    package: package,
                    version: version,
                    signature: signature.data,
                    signatureFormat: signature.format,
                    content: content,
                    configuration: configuration,
                    observabilityScope: observabilityScope,
                    completion: completion
                )
            case .failure(let error):
                guard let onUnsigned = configuration.onUnsigned else {
                    return completion(.failure(
                        RegistryError
                            .missingConfiguration(details: "security.signing.onUnsigned")
                    ))
                }

                switch onUnsigned {
                case .error:
                    completion(.failure(error))
                case .prompt:
                    if case RegistryError.sourceArchiveNotSigned = error {
                        // Source archive is not signed
                        // TODO: Call delegate to prompt user to continue with unsigned package or error.
                    } else {
                        // Cannot determine if source archive is signed or not
                        // TODO: Call delegate to prompt user to continue with package as if it were unsigned or error.
                    }
                case .warn:
                    observabilityScope.emit(warning: "\(error)")
                    completion(.success(.none))
                case .silentAllow:
                    // Continue without logging
                    completion(.success(.none))
                }
            }
        }
    }

    private func validateSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signature: Data,
        signatureFormat: SignatureFormat,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        observabilityScope: ObservabilityScope,
        completion: @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        #if swift(>=5.5.2)
        Task {
            do {
                let signatureStatus = try await SignatureProvider.status(
                    of: signature,
                    for: content,
                    in: signatureFormat,
                    // TODO: load trusted roots (trustedRootCertificatesPath, includeDefaultTrustedRootCertificates)
                    // TODO: build policy set (validationChecks)
                    verifierConfiguration: .init(),
                    observabilityScope: observabilityScope
                )

                switch signatureStatus {
                case .valid(let signingEntity):
                    completion(.success(signingEntity))
                case .invalid(let reason):
                    completion(.failure(RegistryError.invalidSignature(reason: reason)))
                case .certificateInvalid(let reason):
                    completion(.failure(RegistryError.invalidSigningCertificate(reason: reason)))
                case .certificateNotTrusted:
                    guard let onUntrusted = configuration.onUntrustedCertificate else {
                        return completion(.failure(
                            RegistryError
                                .missingConfiguration(details: "security.signing.onUntrustedCertificate")
                        ))
                    }

                    switch onUntrusted {
                    case .error:
                        // TODO: populate error with signer detail
                        completion(.failure(RegistryError.signerNotTrusted))
                    case .prompt:
                        // TODO: Call delegate to prompt user to continue with package or error.
                        ()
                    case .warn:
                        // TODO: populate error with signer detail
                        observabilityScope.emit(warning: "\(RegistryError.signerNotTrusted)")
                        completion(.success(.none))
                    case .silentAllow:
                        // Continue without logging
                        completion(.success(.none))
                    }
                }
            } catch {
                completion(.failure(RegistryError.failedToValidateSignature(error)))
            }
        }
        #else
        completion(.success(.none))
        #endif
    }

    private func getSourceArchiveSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        timeout: DispatchTimeInterval?,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<(data: Data, format: SignatureFormat), Error>) -> Void
    ) {
        self.registryClient.getRawPackageVersionMetadata(
            registry: registry,
            package: package,
            version: version,
            timeout: timeout,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let metadata):
                guard let sourceArchive = metadata.sourceArchive else {
                    return completion(.failure(RegistryError.missingSourceArchive))
                }
                guard let signatureBase64Encoded = sourceArchive.signing?.signatureBase64Encoded else {
                    return completion(.failure(RegistryError.sourceArchiveNotSigned(
                        registry: registry,
                        package: package.underlying,
                        version: version
                    )))
                }
                guard let signatureData = Data(base64Encoded: signatureBase64Encoded) else {
                    return completion(.failure(RegistryError.failedLoadingSignature))
                }
                guard let signatureFormatString = sourceArchive.signing?.signatureFormat else {
                    return completion(.failure(RegistryError.missingSignatureFormat))
                }
                guard let signatureFormat = SignatureFormat(rawValue: signatureFormatString) else {
                    return completion(.failure(RegistryError.unknownSignatureFormat(signatureFormatString)))
                }
                completion(.success((signatureData, signatureFormat)))
            case .failure(let error):
                let actualError: Error
                if case RegistryError.failedRetrievingReleaseInfo(_, _, _, let error) = error {
                    actualError = error
                } else {
                    actualError = error
                }
                completion(.failure(RegistryError.failedRetrievingSourceArchiveSignature(
                    registry: registry,
                    package: package.underlying,
                    version: version,
                    error: actualError
                )))
            }
        }
    }
}
