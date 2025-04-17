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

import Dispatch
import Foundation

import Basics

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SwiftASN1
@_implementationOnly import X509
#else
import SwiftASN1
import X509
#endif

public enum CertificatePolicyKey: Hashable, CustomStringConvertible {
    case `default`(subjectUserID: String? = nil, subjectOrganizationalUnit: String? = nil)
    case appleSwiftPackageCollection(subjectUserID: String? = nil, subjectOrganizationalUnit: String? = nil)

    @available(*, deprecated, message: "use `appleSwiftPackageCollection` instead")
    case appleDistribution(subjectUserID: String? = nil, subjectOrganizationalUnit: String? = nil)

    /// For testing only
    case custom

    public var description: String {
        switch self {
        case .default(let userID, let organizationalUnit):
            return "Default certificate policy\(userID.map { " (userID: \($0))" } ?? "")\(organizationalUnit.map { " (organizationalUnit: \($0))" } ?? "")"
        case .appleSwiftPackageCollection(let userID, let organizationalUnit):
            return "Swift Package Collection certificate policy\(userID.map { " (userID: \($0))" } ?? "")\(organizationalUnit.map { " (organizationalUnit: \($0))" } ?? "")"
        case .appleDistribution(let userID, let organizationalUnit):
            return "Distribution certificate policy\(userID.map { " (userID: \($0))" } ?? "")\(organizationalUnit.map { " (organizationalUnit: \($0))" } ?? "")"
        case .custom:
            return "Custom certificate policy"
        }
    }

    public static let `default` = CertificatePolicyKey.default()
    public static let appleSwiftPackageCollection = CertificatePolicyKey.appleSwiftPackageCollection()
    @available(*, deprecated, message: "use `appleSwiftPackageCollection` instead")
    public static let appleDistribution = CertificatePolicyKey.appleDistribution()
}

// MARK: - Certificate policies

protocol CertificatePolicy {
    /// Validates the given certificate chain.
    ///
    /// - Parameters:
    ///   - certChain: The certificate being verified must be the first element of the array, with its issuer the next
    ///                element and so on, and the root CA certificate is last.
    ///   - validationTime: Overrides the timestamp used for checking certificate expiry (e.g., for testing).
    ///                     By default the current time is used.
    func validate(certChain: [Certificate], validationTime: Date) async throws
}

extension CertificatePolicy {
    /// Validates the given certificate chain.
    ///
    /// - Parameters:
    ///   - certChain: The certificate being verified must be the first element of the array, with its issuer the next
    ///                element and so on, and the root CA certificate is last.
    func validate(certChain: [Certificate]) async throws {
        try await self.validate(certChain: certChain, validationTime: Date())
    }

    func verify(
        certChain: [Certificate],
        trustedRoots: [Certificate]?,
        @PolicyBuilder policies: () -> some VerifierPolicy,
        observabilityScope: ObservabilityScope
    ) async throws {
        guard !certChain.isEmpty else {
            throw CertificatePolicyError.emptyCertChain
        }

        let policies = policies()

        var trustStore = CertificateStores.defaultTrustRoots
        if let trustedRoots {
            trustStore.append(contentsOf: trustedRoots)
        }

        guard !trustStore.isEmpty else {
            throw CertificatePolicyError.noTrustedRootCertsConfigured
        }

        var verifier = Verifier(rootCertificates: CertificateStore(trustStore)) {
            policies
        }
        let result = await verifier.validate(
            leafCertificate: certChain[0],
            intermediates: CertificateStore(certChain)
        )

        switch result {
        case .validCertificate:
            return
        case .couldNotValidate(let failures):
            observabilityScope.emit(error: "Failed to validate certificate chain \(certChain): \(failures)")
            throw CertificatePolicyError.invalidCertChain
        }
    }
}

enum CertificatePolicyError: Error, Equatable {
    case noTrustedRootCertsConfigured
    case emptyCertChain
    case invalidCertChain
}

/// Default policy for validating certificates used to sign package collections.
///
/// Certificates must satisfy these conditions:
///   - The timestamp at which signing/verification is done must fall within the signing certificate’s validity period.
///   - The certificate’s “Extended Key Usage” extension must include “Code Signing”.
///   - The certificate must use either 256-bit EC (recommended) or 2048-bit RSA key.
///   - The certificate must not be revoked. The certificate authority must support OCSP.
///   - The certificate chain is valid and root certificate must be trusted.
struct DefaultCertificatePolicy: CertificatePolicy {
    let trustedRoots: [Certificate]
    let expectedSubjectUserID: String?
    let expectedSubjectOrganizationalUnit: String?

    private let httpClient: HTTPClient
    private let observabilityScope: ObservabilityScope

    /// Initializes a `DefaultCertificatePolicy`.
    ///
    /// - Parameters:
    ///   - trustedRootCertsDir: Users may specify root certificates in addition to SwiftPM's default trust
    ///                          store by placing them in this directory.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`.
    ///                                 The difference between this and `trustedRootCertsDir` is that the latter is
    ///                                 user configured and dynamic, while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - expectedSubjectOrganizationalUnit: The subject organizational unit name that must match if specified.
    init(
        trustedRootCertsDir: URL?,
        additionalTrustedRootCerts: [Certificate]?,
        expectedSubjectUserID: String? = nil,
        expectedSubjectOrganizationalUnit: String? = nil,
        observabilityScope: ObservabilityScope
    ) {
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots
                .append(contentsOf: Self.loadCerts(at: trustedRootCertsDir, observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.expectedSubjectOrganizationalUnit = expectedSubjectOrganizationalUnit
        self.httpClient = HTTPClient.makeDefault()
        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], validationTime: Date) async throws {
        guard !certChain.isEmpty else {
            throw CertificatePolicyError.emptyCertChain
        }

        try await self.verify(
            certChain: certChain,
            trustedRoots: self.trustedRoots,
            policies: {
                _ADPCertificatePolicy() // included for testing
                // Check if subject name matches
                _SubjectNamePolicy(
                    expectedUserID: self.expectedSubjectUserID,
                    expectedOrganizationalUnit: self.expectedSubjectOrganizationalUnit
                )
                // Must be a code signing certificate
                _CodeSigningPolicy()
                // Basic validations including expiry check
                RFC5280Policy(validationTime: validationTime)
                // Must support OCSP
                _OCSPVerifierPolicy(
                    httpClient: self.httpClient,
                    validationTime: validationTime
                )
            },
            observabilityScope: self.observabilityScope
        )
    }
}

/// Policy for validating developer.apple.com Swift Package Collection certificates.
///
/// This has the same requirements as `DefaultCertificatePolicy` plus additional
/// marker extensions for Swift Package Collection certifiicates.
struct ADPSwiftPackageCollectionCertificatePolicy: CertificatePolicy {
    let trustedRoots: [Certificate]
    let expectedSubjectUserID: String?
    let expectedSubjectOrganizationalUnit: String?

    private let httpClient: HTTPClient
    private let observabilityScope: ObservabilityScope

    /// Initializes a `ADPSwiftPackageCollectionCertificatePolicy`.
    ///
    /// - Parameters:
    ///   - trustedRootCertsDir: Users may specify root certificates in addition to SwiftPM's default trust
    ///                          store by placing them in this directory.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`.
    ///                                 The difference between this and `trustedRootCertsDir` is that the latter is
    ///                                 user configured and dynamic, while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - expectedSubjectOrganizationalUnit: The subject organizational unit name that must match if specified.
    init(
        trustedRootCertsDir: URL?,
        additionalTrustedRootCerts: [Certificate]?,
        expectedSubjectUserID: String? = nil,
        expectedSubjectOrganizationalUnit: String? = nil,
        observabilityScope: ObservabilityScope
    ) {
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots
                .append(contentsOf: Self.loadCerts(at: trustedRootCertsDir, observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.expectedSubjectOrganizationalUnit = expectedSubjectOrganizationalUnit
        self.httpClient = HTTPClient.makeDefault()
        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], validationTime: Date) async throws {
        guard !certChain.isEmpty else {
            throw CertificatePolicyError.emptyCertChain
        }

        try await self.verify(
            certChain: certChain,
            trustedRoots: self.trustedRoots,
            policies: {
                // Check for specific markers
                _ADPSwiftPackageCertificatePolicy()
                _ADPCertificatePolicy() // included for testing
                // Check if subject name matches
                _SubjectNamePolicy(
                    expectedUserID: self.expectedSubjectUserID,
                    expectedOrganizationalUnit: self.expectedSubjectOrganizationalUnit
                )
                // Must be a code signing certificate
                _CodeSigningPolicy()
                // Basic validations including expiry check
                RFC5280Policy(validationTime: validationTime)
                // Must support OCSP
                _OCSPVerifierPolicy(
                    httpClient: self.httpClient,
                    validationTime: validationTime
                )
            },
            observabilityScope: self.observabilityScope
        )
    }
}

/// Policy for validating developer.apple.com Apple Distribution certificates.
///
/// This has the same requirements as `DefaultCertificatePolicy` plus additional
/// marker extensions for Apple Distribution certifiicates.
struct ADPAppleDistributionCertificatePolicy: CertificatePolicy {
    let trustedRoots: [Certificate]
    let expectedSubjectUserID: String?
    let expectedSubjectOrganizationalUnit: String?

    private let httpClient: HTTPClient
    private let observabilityScope: ObservabilityScope

    /// Initializes a `ADPAppleDistributionCertificatePolicy`.
    ///
    /// - Parameters:
    ///   - trustedRootCertsDir: Users may specify root certificates in addition to SwiftPM's default trust
    ///                          store by placing them in this directory.
    ///   - additionalTrustedRootCerts: Root certificates to be trusted in addition to those in `trustedRootCertsDir`.
    ///                                 The difference between this and `trustedRootCertsDir` is that the latter is
    ///                                 user configured and dynamic, while this is configured by SwiftPM and static.
    ///   - expectedSubjectUserID: The subject user ID that must match if specified.
    ///   - expectedSubjectOrganizationalUnit: The subject organizational unit name that must match if specified.
    init(
        trustedRootCertsDir: URL?,
        additionalTrustedRootCerts: [Certificate]?,
        expectedSubjectUserID: String? = nil,
        expectedSubjectOrganizationalUnit: String? = nil,
        observabilityScope: ObservabilityScope
    ) {
        var trustedRoots = [Certificate]()
        if let trustedRootCertsDir {
            trustedRoots
                .append(contentsOf: Self.loadCerts(at: trustedRootCertsDir, observabilityScope: observabilityScope))
        }
        if let additionalTrustedRootCerts {
            trustedRoots.append(contentsOf: additionalTrustedRootCerts)
        }
        self.trustedRoots = trustedRoots
        self.expectedSubjectUserID = expectedSubjectUserID
        self.expectedSubjectOrganizationalUnit = expectedSubjectOrganizationalUnit
        self.httpClient = HTTPClient.makeDefault()
        self.observabilityScope = observabilityScope
    }

    func validate(certChain: [Certificate], validationTime: Date) async throws {
        guard !certChain.isEmpty else {
            throw CertificatePolicyError.emptyCertChain
        }

        try await self.verify(
            certChain: certChain,
            trustedRoots: self.trustedRoots,
            policies: {
                // Check for specific markers
                _ADPAppleDistributionCertificatePolicy()
                _ADPCertificatePolicy() // included for testing
                // Check if subject name matches
                _SubjectNamePolicy(
                    expectedUserID: self.expectedSubjectUserID,
                    expectedOrganizationalUnit: self.expectedSubjectOrganizationalUnit
                )
                // Must be a code signing certificate
                _CodeSigningPolicy()
                // Basic validations including expiry check
                RFC5280Policy(validationTime: validationTime)
                // Must support OCSP
                _OCSPVerifierPolicy(
                    httpClient: self.httpClient,
                    validationTime: validationTime
                )
            },
            observabilityScope: self.observabilityScope
        )
    }
}

// MARK: - Verifier policies

/// Policy for code signing certificates.
struct _CodeSigningPolicy: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        ASN1ObjectIdentifier.X509ExtensionID.keyUsage,
        ASN1ObjectIdentifier.X509ExtensionID.extendedKeyUsage,
    ]

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        let isCodeSigning = (
            try? chain.leaf.extensions.extendedKeyUsage?.contains(ExtendedKeyUsage.Usage.codeSigning)
        ) ?? false
        guard isCodeSigning else {
            return .failsToMeetPolicy(reason: "Certificate \(chain.leaf) does not have code signing extended key usage")
        }
        return .meetsPolicy
    }
}

/// Policy for revocation check via OCSP.
struct _OCSPVerifierPolicy: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    private static let cacheTTL: DispatchTimeInterval = .seconds(5 * 60)
    private let cache = ThreadSafeKeyValueStore<
        UnverifiedCertificateChain,
        (result: PolicyEvaluationResult, expires: DispatchTime)
    >()

    private var underlying: OCSPVerifierPolicy<_OCSPRequester>

    init(httpClient: HTTPClient, validationTime: Date) {
        self.underlying = OCSPVerifierPolicy(
            failureMode: .soft,
            requester: _OCSPRequester(httpClient: httpClient),
            validationTime: validationTime
        )
    }

    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        // Look for cached result
        if let cached = self.cache[chain], cached.expires < .now() {
            return cached.result
        }

        // This makes HTTP requests
        let result = await self.underlying.chainMeetsPolicyRequirements(chain: chain)

        // Save result to cache
        self.cache[chain] = (result: result, expires: .now() + Self.cacheTTL)
        return result
    }
}

private struct _OCSPRequester: OCSPRequester {
    let httpClient: HTTPClient

    func query(request: [UInt8], uri: String) async -> OCSPRequesterQueryResult {
        guard let url = URL(string: uri), let host = url.host else {
            return .terminalError(SwiftOCSPRequesterError.invalidURL(uri))
        }

        do {
            let response = try await self.httpClient.post(
                url,
                body: Data(request),
                headers: [
                    "Content-Type": "application/ocsp-request",
                    "Host": host,
                ]
            )

            guard response.statusCode == 200 else {
                throw SwiftOCSPRequesterError.invalidResponse(statusCode: response.statusCode)
            }
            guard let responseBody = response.body else {
                throw SwiftOCSPRequesterError.emptyResponse
            }
            return .response(Array(responseBody))
        } catch {
            return .nonTerminalError(error)
        }
    }
}

enum SwiftOCSPRequesterError: Error {
    case invalidURL(String)
    case emptyResponse
    case invalidResponse(statusCode: Int)
}

/// Policy for matching subject name.
struct _SubjectNamePolicy: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    let expectedUserID: String?
    let expectedOrganizationalUnit: String?

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        if let expectedUserID {
            let userID = chain.leaf.subject.userID
            guard userID == expectedUserID else {
                return .failsToMeetPolicy(
                    reason: "Subject user ID '\(String(describing: userID))' does not match expected '\(expectedUserID)'"
                )
            }
        }

        if let expectedOrganizationalUnit {
            let organizationUnit = chain.leaf.subject.organizationalUnitName
            guard organizationUnit == expectedOrganizationalUnit else {
                return .failsToMeetPolicy(
                    reason: "Subject organizational unit name '\(String(describing: organizationUnit))' does not match expected '\(expectedOrganizationalUnit)'"
                )
            }
        }

        return .meetsPolicy
    }
}

/// Policy for ADP certificates.
struct _ADPCertificatePolicy: VerifierPolicy {
    /// Include custom marker extensions (which can be critical) so they would not
    /// be considered unhandled and cause certificate chain validation to fail.
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] =
        ASN1ObjectIdentifier.NameAttributes.adpAppleDevelopmentMarkers // included for testing

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        // Not policing anything here. This policy is mainly for
        // listing marker extensions to prevent chain validation
        // from failing prematurely.
        .meetsPolicy
    }
}

/// Policy for ADP Swift Package (Collection) certificates.
struct _ADPSwiftPackageCertificatePolicy: VerifierPolicy {
    /// Include custom marker extensions (which can be critical) so they would not
    /// be considered unhandled and cause certificate chain validation to fail.
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        ASN1ObjectIdentifier.NameAttributes.adpSwiftPackageCollectionMarker,
        ASN1ObjectIdentifier.NameAttributes.adpSwiftPackageMarker,
    ]

    // developer.apple.com cert chain is always 3-long
    private static let expectedCertChainLength = 3

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        guard chain.count == Self.expectedCertChainLength else {
            return .failsToMeetPolicy(
                reason: "Certificate chain should have length \(Self.expectedCertChainLength) but it's \(chain.count)"
            )
        }

        // Package collection can be signed with "Swift Package Collection"
        // or "Swift Package" certificate
        guard chain.leaf.hasExtension(oid: ASN1ObjectIdentifier.NameAttributes.adpSwiftPackageCollectionMarker)
            || chain.leaf.hasExtension(oid: ASN1ObjectIdentifier.NameAttributes.adpSwiftPackageMarker)
        else {
            return .failsToMeetPolicy(reason: "Leaf certificate missing marker OID")
        }

        for marker in ASN1ObjectIdentifier.NameAttributes.wwdrIntermediateMarkers {
            if chain[1].hasExtension(oid: marker) {
                return .meetsPolicy
            }
        }
        return .failsToMeetPolicy(reason: "Intermediate missing marker OID")
    }
}

/// Policy for ADP Apple Distribution certificates.
struct _ADPAppleDistributionCertificatePolicy: VerifierPolicy {
    /// Include custom marker extensions (which can be critical) so they would not
    /// be considered unhandled and cause certificate chain validation to fail.
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] =
        ASN1ObjectIdentifier.NameAttributes.adpAppleDistributionMarkers

    // developer.apple.com cert chain is always 3-long
    private static let expectedCertChainLength = 3

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        guard chain.count == Self.expectedCertChainLength else {
            return .failsToMeetPolicy(
                reason: "Certificate chain should have length \(Self.expectedCertChainLength) but it's \(chain.count)"
            )
        }

        var hasMarker = false
        for marker in ASN1ObjectIdentifier.NameAttributes.adpAppleDistributionMarkers {
            if chain.leaf.hasExtension(oid: marker) {
                hasMarker = true
                break
            }
        }
        guard hasMarker else {
            return .failsToMeetPolicy(reason: "Leaf certificate missing marker OID")
        }

        for marker in ASN1ObjectIdentifier.NameAttributes.wwdrIntermediateMarkers {
            if chain[1].hasExtension(oid: marker) {
                return .meetsPolicy
            }
        }
        return .failsToMeetPolicy(reason: "Intermediate missing marker OID")
    }
}

// MARK: - Default trust store

enum Certificates {
    static let appleRootsRaw = [
        PackageResources.AppleComputerRootCertificate_cer,
        PackageResources.AppleIncRootCertificate_cer,
        PackageResources.AppleRootCA_G2_cer,
        PackageResources.AppleRootCA_G3_cer,
    ]

    static let appleRoots = Self.appleRootsRaw.compactMap {
        try? Certificate(derEncoded: $0)
    }
}

enum CertificateStores {
    static let defaultTrustRoots = Certificates.appleRoots
}

// MARK: - Utils

extension CertificatePolicy {
    fileprivate static func loadCerts(at directory: URL, observabilityScope: ObservabilityScope) -> [Certificate] {
        var certs = [Certificate]()
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                do {
                    let certData = try Data(contentsOf: fileURL)
                    certs.append(try Certificate(derEncoded: Array(certData)))
                } catch {
                    observabilityScope.emit(
                        warning: "The certificate \(fileURL) is invalid",
                        underlyingError: error
                    )
                }
            }
        }
        return certs
    }
}

extension HTTPClient {
    fileprivate static func makeDefault() -> HTTPClient {
        var httpClientConfig = HTTPClientConfiguration()
        httpClientConfig.requestTimeout = .seconds(1)
        return HTTPClient(configuration: httpClientConfig)
    }
}
