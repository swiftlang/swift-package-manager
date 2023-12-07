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

import _Concurrency
import Dispatch
import struct Foundation.Data

import Basics
import PackageLoading
import PackageModel
import PackageSigning

import struct TSCUtility.Version

protocol SignatureValidationDelegate {
    func onUnsigned(registry: Registry, package: PackageIdentity, version: Version, completion: (Bool) -> Void)
    func onUntrusted(registry: Registry, package: PackageIdentity, version: Version, completion: (Bool) -> Void)
}

struct SignatureValidation {
    typealias Delegate = SignatureValidationDelegate

    private let skipSignatureValidation: Bool
    private let signingEntityTOFU: PackageSigningEntityTOFU
    private let versionMetadataProvider: (PackageIdentity.RegistryIdentity, Version) throws -> RegistryClient
        .PackageVersionMetadata
    private let delegate: Delegate

    init(
        skipSignatureValidation: Bool,
        signingEntityStorage: PackageSigningEntityStorage?,
        signingEntityCheckingMode: SigningEntityCheckingMode,
        versionMetadataProvider: @escaping (PackageIdentity.RegistryIdentity, Version) throws -> RegistryClient
            .PackageVersionMetadata,
        delegate: Delegate
    ) {
        self.skipSignatureValidation = skipSignatureValidation
        self.signingEntityTOFU = PackageSigningEntityTOFU(
            signingEntityStorage: signingEntityStorage,
            signingEntityCheckingMode: signingEntityCheckingMode
        )
        self.versionMetadataProvider = versionMetadataProvider
        self.delegate = delegate
    }

    // MARK: - source archive
    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws -> SigningEntity? {
        try await safe_async {
            self.validate(
                registry: registry,
                package: package,
                version: version, 
                content: content,
                configuration: configuration,
                timeout: timeout,
                fileSystem: fileSystem,
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
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        guard !self.skipSignatureValidation else {
            return completion(.success(.none))
        }

        self.getAndValidateSourceArchiveSignature(
            registry: registry,
            package: package,
            version: version,
            content: content,
            configuration: configuration,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let signingEntity):
                // Always do signing entity TOFU check at the end,
                // whether the package is signed or not.
                self.signingEntityTOFU.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    signingEntity: signingEntity,
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue
                ) { _ in
                    completion(.success(signingEntity))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func getAndValidateSourceArchiveSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        do {
            let versionMetadata = try self.versionMetadataProvider(package, version)

            guard let sourceArchiveResource = versionMetadata.sourceArchive else {
                throw RegistryError.missingSourceArchive
            }
            guard let signatureBase64Encoded = sourceArchiveResource.signing?.signatureBase64Encoded else {
                throw RegistryError.sourceArchiveNotSigned(
                    registry: registry,
                    package: package.underlying,
                    version: version
                )
            }

            guard let signatureData = Data(base64Encoded: signatureBase64Encoded) else {
                throw RegistryError.failedLoadingSignature
            }
            guard let signatureFormatString = sourceArchiveResource.signing?.signatureFormat else {
                throw RegistryError.missingSignatureFormat
            }
            guard let signatureFormat = SignatureFormat(rawValue: signatureFormatString) else {
                throw RegistryError.unknownSignatureFormat(signatureFormatString)
            }

            self.validateSourceArchiveSignature(
                registry: registry,
                package: package,
                version: version,
                signature: Array(signatureData),
                signatureFormat: signatureFormat,
                content: Array(content),
                configuration: configuration,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                completion: completion
            )
        } catch RegistryError.sourceArchiveNotSigned {
            observabilityScope.emit(
                info: "\(package) \(version) from \(registry) is unsigned",
                metadata: .registryPackageMetadata(identity: package)
            )
            guard let onUnsigned = configuration.onUnsigned else {
                return completion(.failure(RegistryError.missingConfiguration(details: "security.signing.onUnsigned")))
            }

            let sourceArchiveNotSignedError = RegistryError.sourceArchiveNotSigned(
                registry: registry,
                package: package.underlying,
                version: version
            )

            switch onUnsigned {
            case .prompt:
                self.delegate
                    .onUnsigned(registry: registry, package: package.underlying, version: version) { `continue` in
                        if `continue` {
                            completion(.success(.none))
                        } else {
                            completion(.failure(sourceArchiveNotSignedError))
                        }
                    }
            case .error:
                completion(.failure(sourceArchiveNotSignedError))
            case .warn:
                observabilityScope.emit(
                    warning: "\(sourceArchiveNotSignedError)",
                    metadata: .registryPackageMetadata(identity: package)
                )
                completion(.success(.none))
            case .silentAllow:
                // Continue without logging
                completion(.success(.none))
            }
        } catch RegistryError.failedRetrievingReleaseInfo(_, _, _, let error) {
            completion(.failure(RegistryError.failedRetrievingSourceArchiveSignature(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )))
        } catch {
            completion(.failure(RegistryError.failedRetrievingSourceArchiveSignature(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )))
        }
    }

    private func validateSourceArchiveSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        signature: [UInt8],
        signatureFormat: SignatureFormat,
        content: [UInt8],
        configuration: RegistryConfiguration.Security.Signing,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        Task {
            do {
                let signatureStatus = try await SignatureProvider.status(
                    signature: signature,
                    content: content,
                    format: signatureFormat,
                    verifierConfiguration: try VerifierConfiguration.from(configuration, fileSystem: fileSystem),
                    observabilityScope: observabilityScope
                )

                switch signatureStatus {
                case .valid(let signingEntity):
                    observabilityScope
                        .emit(
                            info: "\(package) \(version) from \(registry) is signed with a valid entity '\(signingEntity)'"
                        )
                    completion(.success(signingEntity))
                case .invalid(let reason):
                    completion(.failure(RegistryError.invalidSignature(reason: reason)))
                case .certificateInvalid(let reason):
                    completion(.failure(RegistryError.invalidSigningCertificate(reason: reason)))
                case .certificateNotTrusted(let signingEntity):
                    observabilityScope
                        .emit(
                            info: "\(package) \(version) from \(registry) signing entity '\(signingEntity)' is untrusted",
                            metadata: .registryPackageMetadata(identity: package)
                        )

                    guard let onUntrusted = configuration.onUntrustedCertificate else {
                        return completion(.failure(
                            RegistryError.missingConfiguration(details: "security.signing.onUntrustedCertificate")
                        ))
                    }

                    let signerNotTrustedError = RegistryError.signerNotTrusted(package.underlying, signingEntity)

                    switch onUntrusted {
                    case .prompt:
                        self.delegate
                            .onUntrusted(
                                registry: registry,
                                package: package.underlying,
                                version: version
                            ) { `continue` in
                                if `continue` {
                                    completion(.success(.none))
                                } else {
                                    completion(.failure(signerNotTrustedError))
                                }
                            }
                    case .error:
                        completion(.failure(signerNotTrustedError))
                    case .warn:
                        observabilityScope.emit(
                            warning: "\(signerNotTrustedError)",
                            metadata: .registryPackageMetadata(identity: package)
                        )
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
    }

    // MARK: - manifests
    func validate(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        toolsVersion: ToolsVersion?,
        manifestContent: String,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue
    ) async throws -> SigningEntity? {
        try await safe_async {
            self.validate(
                registry: registry,
                package: package,
                version: version,
                toolsVersion: toolsVersion,
                manifestContent: manifestContent,
                configuration: configuration,
                timeout: timeout,
                fileSystem:fileSystem,
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
        toolsVersion: ToolsVersion?,
        manifestContent: String,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        guard !self.skipSignatureValidation else {
            return completion(.success(.none))
        }

        self.getAndValidateManifestSignature(
            registry: registry,
            package: package,
            version: version,
            toolsVersion: toolsVersion,
            manifestContent: manifestContent,
            configuration: configuration,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue
        ) { result in
            switch result {
            case .success(let signingEntity):
                // Always do signing entity TOFU check at the end,
                // whether the manifest is signed or not.
                self.signingEntityTOFU.validate(
                    registry: registry,
                    package: package,
                    version: version,
                    signingEntity: signingEntity,
                    observabilityScope: observabilityScope,
                    callbackQueue: callbackQueue
                ) { _ in
                    completion(.success(signingEntity))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func getAndValidateManifestSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        toolsVersion: ToolsVersion?,
        manifestContent: String,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        let manifestName = toolsVersion.map { "Package@swift-\($0).swift" } ?? Manifest.filename

        do {
            let versionMetadata = try self.versionMetadataProvider(package, version)

            guard let sourceArchiveResource = versionMetadata.sourceArchive else {
                observabilityScope
                    .emit(
                        debug: "cannot determine if \(manifestName) should be signed because source archive for \(package) \(version) is not found in \(registry)",
                        metadata: .registryPackageMetadata(identity: package)
                    )
                return completion(.success(.none))
            }
            guard sourceArchiveResource.signing?.signatureBase64Encoded != nil else {
                throw RegistryError.sourceArchiveNotSigned(
                    registry: registry,
                    package: package.underlying,
                    version: version
                )
            }

            // source archive is signed, so the manifest must also be signed
            guard let manifestSignature = try ManifestSignatureParser.parse(utf8String: manifestContent) else {
                return completion(.failure(RegistryError.manifestNotSigned(
                    registry: registry,
                    package: package.underlying,
                    version: version,
                    toolsVersion: toolsVersion
                )))
            }

            guard let signatureFormat = SignatureFormat(rawValue: manifestSignature.signatureFormat) else {
                return completion(.failure(RegistryError.unknownSignatureFormat(manifestSignature.signatureFormat)))
            }

            self.validateManifestSignature(
                registry: registry,
                package: package,
                version: version,
                manifestName: manifestName,
                signature: manifestSignature.signature,
                signatureFormat: signatureFormat,
                content: manifestSignature.contents,
                configuration: configuration,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                completion: completion
            )
        } catch RegistryError.sourceArchiveNotSigned {
            observabilityScope.emit(
                debug: "\(manifestName) is not signed because source archive for \(package) \(version) from \(registry) is not signed",
                metadata: .registryPackageMetadata(identity: package)
            )
            guard let onUnsigned = configuration.onUnsigned else {
                return completion(.failure(RegistryError.missingConfiguration(details: "security.signing.onUnsigned")))
            }

            let sourceArchiveNotSignedError = RegistryError.sourceArchiveNotSigned(
                registry: registry,
                package: package.underlying,
                version: version
            )

            // Prompt if configured, otherwise just continue (this differs
            // from source archive to minimize duplicate loggings).
            switch onUnsigned {
            case .prompt:
                self.delegate
                    .onUnsigned(registry: registry, package: package.underlying, version: version) { `continue` in
                        if `continue` {
                            completion(.success(.none))
                        } else {
                            completion(.failure(sourceArchiveNotSignedError))
                        }
                    }
            default:
                completion(.success(.none))
            }
        } catch ManifestSignatureParser.Error.malformedManifestSignature {
            completion(.failure(RegistryError.invalidSignature(reason: "manifest signature is malformed")))
        } catch {
            observabilityScope
                .emit(
                    debug: "cannot determine if \(manifestName) should be signed because retrieval of source archive signature for \(package) \(version) from \(registry) failed",
                    metadata: .registryPackageMetadata(identity: package),
                    underlyingError: error
                )
            completion(.success(.none))
        }
    }

    private func validateManifestSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        manifestName: String,
        signature: [UInt8],
        signatureFormat: SignatureFormat,
        content: [UInt8],
        configuration: RegistryConfiguration.Security.Signing,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        Task {
            do {
                let signatureStatus = try await SignatureProvider.status(
                    signature: signature,
                    content: content,
                    format: signatureFormat,
                    verifierConfiguration: try VerifierConfiguration.from(configuration, fileSystem: fileSystem),
                    observabilityScope: observabilityScope
                )

                switch signatureStatus {
                case .valid(let signingEntity):
                    observabilityScope
                        .emit(
                            info: "\(package) \(version) \(manifestName) from \(registry) is signed with a valid entity '\(signingEntity)'"
                        )
                    completion(.success(signingEntity))
                case .invalid(let reason):
                    completion(.failure(RegistryError.invalidSignature(reason: reason)))
                case .certificateInvalid(let reason):
                    completion(.failure(RegistryError.invalidSigningCertificate(reason: reason)))
                case .certificateNotTrusted(let signingEntity):
                    observabilityScope
                        .emit(
                            debug: "the signer '\(signingEntity)' of \(package) \(version) \(manifestName) from \(registry) is not trusted",
                            metadata: .registryPackageMetadata(identity: package)
                        )

                    guard let onUntrusted = configuration.onUntrustedCertificate else {
                        return completion(.failure(
                            RegistryError.missingConfiguration(details: "security.signing.onUntrustedCertificate")
                        ))
                    }

                    let signerNotTrustedError = RegistryError.signerNotTrusted(package.underlying, signingEntity)

                    // Prompt if configured, otherwise just continue (this differs
                    // from source archive to minimize duplicate loggings).
                    switch onUntrusted {
                    case .prompt:
                        self.delegate
                            .onUntrusted(
                                registry: registry,
                                package: package.underlying,
                                version: version
                            ) { `continue` in
                                if `continue` {
                                    completion(.success(.none))
                                } else {
                                    completion(.failure(signerNotTrustedError))
                                }
                            }
                    default:
                        completion(.success(.none))
                    }
                }
            } catch {
                completion(.failure(RegistryError.failedToValidateSignature(error)))
            }
        }
    }

    // MARK: - signing entity

    static func extractSigningEntity(
        signature: [UInt8],
        signatureFormat: SignatureFormat,
        configuration: RegistryConfiguration.Security.Signing,
        fileSystem: FileSystem,
        completion: @Sendable @escaping (Result<SigningEntity?, Error>) -> Void
    ) {
        Task {
            do {
                let verifierConfiguration = try VerifierConfiguration.from(configuration, fileSystem: fileSystem)
                let signingEntity = try await SignatureProvider.extractSigningEntity(
                    signature: signature,
                    format: signatureFormat,
                    verifierConfiguration: verifierConfiguration
                )
                return completion(.success(signingEntity))
            } catch {
                return completion(.failure(error))
            }
        }
    }
}

extension VerifierConfiguration {
    fileprivate static func from(
        _ configuration: RegistryConfiguration.Security.Signing,
        fileSystem: FileSystem
    ) throws -> VerifierConfiguration {
        var verifierConfiguration = VerifierConfiguration()

        // Load trusted roots from configured directory
        if let trustedRootsDirectoryPath = configuration.trustedRootCertificatesPath {
            let trustedRootsDirectory: AbsolutePath
            do {
                trustedRootsDirectory = try AbsolutePath(validating: trustedRootsDirectoryPath)
            } catch {
                throw RegistryError.badConfiguration(details: "\(trustedRootsDirectoryPath) is invalid: \(error.interpolationDescription)")
            }

            guard fileSystem.isDirectory(trustedRootsDirectory) else {
                throw RegistryError.badConfiguration(details: "\(trustedRootsDirectoryPath) is not a directory")
            }

            do {
                let trustedRoots = try fileSystem.getDirectoryContents(trustedRootsDirectory).map {
                    let trustRootPath = trustedRootsDirectory.appending(component: $0)
                    return try fileSystem.readFileContents(trustRootPath).contents
                }
                verifierConfiguration.trustedRoots = trustedRoots
            } catch {
                throw RegistryError.badConfiguration(details: "failed to load trust roots: \(error.interpolationDescription)")
            }
        }

        // Should default trust store be included?
        if let includeDefaultTrustedRoots = configuration.includeDefaultTrustedRootCertificates {
            verifierConfiguration.includeDefaultTrustStore = includeDefaultTrustedRoots
        }

        if let validationChecks = configuration.validationChecks {
            // Check certificate expiry
            if let certificateExpiration = validationChecks.certificateExpiration {
                switch certificateExpiration {
                case .enabled:
                    verifierConfiguration.certificateExpiration = .enabled(validationTime: .none)
                case .disabled:
                    verifierConfiguration.certificateExpiration = .disabled
                }
            }
            // Check certificate revocation status
            if let certificateRevocation = validationChecks.certificateRevocation {
                switch certificateRevocation {
                case .strict:
                    verifierConfiguration.certificateRevocation = .strict(validationTime: .none)
                case .allowSoftFail:
                    verifierConfiguration.certificateRevocation = .allowSoftFail(validationTime: .none)
                case .disabled:
                    verifierConfiguration.certificateRevocation = .disabled
                }
            }
        }

        return verifierConfiguration
    }
}

extension ObservabilityMetadata {
    public static func registryPackageMetadata(identity: PackageIdentity.RegistryIdentity) -> Self {
        var metadata = ObservabilityMetadata()
        metadata.packageIdentity = identity.underlying
        metadata.packageKind = .registry(identity.underlying)
        return metadata
    }
}
