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
    func onUnsigned(registry: Registry, package: PackageIdentity, version: Version) async -> Bool
    func onUntrusted(registry: Registry, package: PackageIdentity, version: Version) async -> Bool
}

struct SignatureValidation {
    typealias Delegate = SignatureValidationDelegate

    private let skipSignatureValidation: Bool
    private let signingEntityTOFU: PackageSigningEntityTOFU
    private let versionMetadataProvider: (PackageIdentity.RegistryIdentity, Version) async throws -> RegistryClient
        .PackageVersionMetadata
    private let delegate: Delegate

    init(
        skipSignatureValidation: Bool,
        signingEntityStorage: PackageSigningEntityStorage?,
        signingEntityCheckingMode: SigningEntityCheckingMode,
        versionMetadataProvider: @escaping (PackageIdentity.RegistryIdentity, Version) async throws -> RegistryClient
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
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        guard !self.skipSignatureValidation else {
            return nil
        }

        let signingEntity = try await self.getAndValidateSourceArchiveSignature(
            registry: registry,
            package: package,
            version: version,
            content: content,
            configuration: configuration,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        // Always do signing entity TOFU check at the end,
        // whether the package is signed or not.
        try self.signingEntityTOFU.validate(
            registry: registry,
            package: package,
            version: version,
            signingEntity: signingEntity,
            observabilityScope: observabilityScope
        )

        return signingEntity
    }

    private func getAndValidateSourceArchiveSignature(
        registry: Registry,
        package: PackageIdentity.RegistryIdentity,
        version: Version,
        content: Data,
        configuration: RegistryConfiguration.Security.Signing,
        timeout: DispatchTimeInterval?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        let signatureData: Data
        let signatureFormat: SignatureFormat

        do {
            let versionMetadata = try await self.versionMetadataProvider(package, version)

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

            guard let data = Data(base64Encoded: signatureBase64Encoded) else {
                throw RegistryError.failedLoadingSignature
            }
            signatureData = data

            guard let signatureFormatString = sourceArchiveResource.signing?.signatureFormat else {
                throw RegistryError.missingSignatureFormat
            }
            guard let format = SignatureFormat(rawValue: signatureFormatString) else {
                throw RegistryError.unknownSignatureFormat(signatureFormatString)
            }
            signatureFormat = format
        } catch RegistryError.sourceArchiveNotSigned {
            observabilityScope.emit(
                info: "\(package) \(version) from \(registry) is unsigned",
                metadata: .registryPackageMetadata(identity: package)
            )
            guard let onUnsigned = configuration.onUnsigned else {
                throw RegistryError.missingConfiguration(details: "security.signing.onUnsigned")
            }

            let sourceArchiveNotSignedError = RegistryError.sourceArchiveNotSigned(
                registry: registry,
                package: package.underlying,
                version: version
            )

            switch onUnsigned {
            case .prompt:
                let `continue` = await self.delegate.onUnsigned(registry: registry, package: package.underlying, version: version)
                if `continue` {
                    return nil
                } else {
                    throw sourceArchiveNotSignedError
                }

            case .error:
                throw sourceArchiveNotSignedError
            case .warn:
                observabilityScope.emit(
                    warning: "\(sourceArchiveNotSignedError)",
                    metadata: .registryPackageMetadata(identity: package)
                )
                return nil

            case .silentAllow:
                // Continue without logging
                return nil
            }
        } catch RegistryError.failedRetrievingReleaseInfo(_, _, _, let error) {
            throw RegistryError.failedRetrievingSourceArchiveSignature(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        } catch {
            throw RegistryError.failedRetrievingSourceArchiveSignature(
                registry: registry,
                package: package.underlying,
                version: version,
                error: error
            )
        }

        return try await self.validateSourceArchiveSignature(
            registry: registry,
            package: package,
            version: version,
            signature: Array(signatureData),
            signatureFormat: signatureFormat,
            content: Array(content),
            configuration: configuration,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
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
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        let signatureStatus: SignatureStatus
        do {
            signatureStatus = try await SignatureProvider.status(
                signature: signature,
                content: content,
                format: signatureFormat,
                verifierConfiguration: try VerifierConfiguration.from(configuration, fileSystem: fileSystem),
                observabilityScope: observabilityScope
            )
        } catch {
            throw RegistryError.failedToValidateSignature(error)
        }

        switch signatureStatus {
        case .valid(let signingEntity):
            observabilityScope.emit(
                info: "\(package) \(version) from \(registry) is signed with a valid entity '\(signingEntity)'"
            )
            return signingEntity

        case .invalid(let reason):
            throw RegistryError.invalidSignature(reason: reason)

        case .certificateInvalid(let reason):
            throw RegistryError.invalidSigningCertificate(reason: reason)

        case .certificateNotTrusted(let signingEntity):
            observabilityScope.emit(
                info: "\(package) \(version) from \(registry) signing entity '\(signingEntity)' is untrusted",
                metadata: .registryPackageMetadata(identity: package)
            )

            guard let onUntrusted = configuration.onUntrustedCertificate else {
                throw RegistryError.missingConfiguration(details: "security.signing.onUntrustedCertificate")
            }

            let signerNotTrustedError = RegistryError.signerNotTrusted(package.underlying, signingEntity)

            switch onUntrusted {
            case .prompt:
                let `continue` = await self.delegate.onUntrusted(
                    registry: registry,
                    package: package.underlying,
                    version: version
                )

                if `continue` {
                    return nil
                } else {
                    throw signerNotTrustedError
                }

            case .error:
                throw signerNotTrustedError

            case .warn:
                observabilityScope.emit(
                    warning: "\(signerNotTrustedError)",
                    metadata: .registryPackageMetadata(identity: package)
                )
                return nil

            case .silentAllow:
                // Continue without logging
                return nil
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
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        guard !self.skipSignatureValidation else {
            return nil
        }

        let signingEntity = try await self.getAndValidateManifestSignature(
            registry: registry,
            package: package,
            version: version,
            toolsVersion: toolsVersion,
            manifestContent: manifestContent,
            configuration: configuration,
            timeout: timeout,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        // Always do signing entity TOFU check at the end,
        // whether the manifest is signed or not.
        try self.signingEntityTOFU.validate(
            registry: registry,
            package: package,
            version: version,
            signingEntity: signingEntity,
            observabilityScope: observabilityScope
        )

        return signingEntity
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
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        let manifestName = toolsVersion.map { "Package@swift-\($0).swift" } ?? Manifest.filename
        do {
            let versionMetadata: RegistryClient.PackageVersionMetadata
            do {
                versionMetadata = try await self.versionMetadataProvider(package, version)
            } catch {
                observabilityScope.emit(
                    debug: "cannot determine if \(manifestName) should be signed because retrieval of source archive signature for \(package) \(version) from \(registry) failed",
                    metadata: .registryPackageMetadata(identity: package),
                    underlyingError: error
                )
                return nil
            }

            guard let sourceArchiveResource = versionMetadata.sourceArchive else {
                observabilityScope.emit(
                    debug: "cannot determine if \(manifestName) should be signed because source archive for \(package) \(version) is not found in \(registry)",
                    metadata: .registryPackageMetadata(identity: package)
                )
                return nil
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
                throw RegistryError.manifestNotSigned(
                    registry: registry,
                    package: package.underlying,
                    version: version,
                    toolsVersion: toolsVersion
                )
            }

            guard let signatureFormat = SignatureFormat(rawValue: manifestSignature.signatureFormat) else {
                throw RegistryError.unknownSignatureFormat(manifestSignature.signatureFormat)
            }

            return try await self.validateManifestSignature(
                registry: registry,
                package: package,
                version: version,
                manifestName: manifestName,
                signature: manifestSignature.signature,
                signatureFormat: signatureFormat,
                content: manifestSignature.contents,
                configuration: configuration,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )
        } catch RegistryError.sourceArchiveNotSigned {
            observabilityScope.emit(
                debug: "\(manifestName) is not signed because source archive for \(package) \(version) from \(registry) is not signed",
                metadata: .registryPackageMetadata(identity: package)
            )
            guard let onUnsigned = configuration.onUnsigned else {
                throw RegistryError.missingConfiguration(details: "security.signing.onUnsigned")
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
                let `continue` = await self.delegate.onUnsigned(registry: registry, package: package.underlying, version: version)
                if `continue` {
                    return nil
                } else {
                    throw sourceArchiveNotSignedError
                }

            default:
                return nil
            }
        } catch ManifestSignatureParser.Error.malformedManifestSignature {
            throw RegistryError.invalidSignature(reason: "manifest signature is malformed")
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
        observabilityScope: ObservabilityScope
    ) async throws -> SigningEntity? {
        let signatureStatus: SignatureStatus

        do {
            signatureStatus = try await SignatureProvider.status(
                signature: signature,
                content: content,
                format: signatureFormat,
                verifierConfiguration: try VerifierConfiguration.from(configuration, fileSystem: fileSystem),
                observabilityScope: observabilityScope
            )
        } catch {
            throw RegistryError.failedToValidateSignature(error)
        }

        switch signatureStatus {
        case .valid(let signingEntity):
            observabilityScope.emit(
                info: "\(package) \(version) \(manifestName) from \(registry) is signed with a valid entity '\(signingEntity)'"
            )
            return signingEntity

        case .invalid(let reason):
            throw RegistryError.invalidSignature(reason: reason)

        case .certificateInvalid(let reason):
            throw RegistryError.invalidSigningCertificate(reason: reason)

        case .certificateNotTrusted(let signingEntity):
            observabilityScope.emit(
                debug: "the signer '\(signingEntity)' of \(package) \(version) \(manifestName) from \(registry) is not trusted",
                metadata: .registryPackageMetadata(identity: package)
            )

            guard let onUntrusted = configuration.onUntrustedCertificate else {
                throw RegistryError.missingConfiguration(details: "security.signing.onUntrustedCertificate")
            }

            let signerNotTrustedError = RegistryError.signerNotTrusted(package.underlying, signingEntity)

            // Prompt if configured, otherwise just continue (this differs
            // from source archive to minimize duplicate loggings).
            switch onUntrusted {
            case .prompt:
                let `continue` = await self.delegate.onUntrusted(
                    registry: registry,
                    package: package.underlying,
                    version: version
                )

                if `continue` {
                    return nil
                } else {
                    throw signerNotTrustedError
                }

            default:
                return nil
            }
        }
    }

    // MARK: - signing entity

    static func extractSigningEntity(
        signature: [UInt8],
        signatureFormat: SignatureFormat,
        configuration: RegistryConfiguration.Security.Signing,
        fileSystem: FileSystem
    ) async throws -> SigningEntity? {
        let verifierConfiguration = try VerifierConfiguration.from(configuration, fileSystem: fileSystem)
        return try await SignatureProvider.extractSigningEntity(
            signature: signature,
            format: signatureFormat,
            verifierConfiguration: verifierConfiguration
        )
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
