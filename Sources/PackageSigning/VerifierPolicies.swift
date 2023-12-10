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
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL

import Basics

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import SwiftASN1
@_implementationOnly @_spi(DisableValidityCheck) import X509
#else
import SwiftASN1
@_spi(DisableValidityCheck) import X509
#endif

extension SignatureProviderProtocol {
    @PolicyBuilder
    func buildPolicySet(configuration: VerifierConfiguration, httpClient: HTTPClient) -> some VerifierPolicy {
        _CodeSigningPolicy()
        _ADPCertificatePolicy()

        let now = Date()
        switch (configuration.certificateExpiration, configuration.certificateRevocation) {
        case (.enabled(let expiryValidationTime), .strict(let revocationValidationTime)):
            RFC5280Policy(validationTime: expiryValidationTime ?? now)
            _OCSPVerifierPolicy(
                failureMode: .hard,
                httpClient: httpClient,
                validationTime: revocationValidationTime ?? now
            )
        case (.enabled(let expiryValidationTime), .allowSoftFail(let revocationValidationTime)):
            RFC5280Policy(validationTime: expiryValidationTime ?? now)
            _OCSPVerifierPolicy(
                failureMode: .soft,
                httpClient: httpClient,
                validationTime: revocationValidationTime ?? now
            )
        case (.enabled(let expiryValidationTime), .disabled):
            RFC5280Policy(validationTime: expiryValidationTime ?? now)
        case (.disabled, .strict(let revocationValidationTime)):
            // Always do expiry check (and before) if revocation check is enabled
            RFC5280Policy(validationTime: revocationValidationTime ?? now)
            _OCSPVerifierPolicy(
                failureMode: .hard,
                httpClient: httpClient,
                validationTime: revocationValidationTime ?? now
            )
        case (.disabled, .allowSoftFail(let revocationValidationTime)):
            // Always do expiry check (and before) if revocation check is enabled
            RFC5280Policy(validationTime: revocationValidationTime ?? now)
            _OCSPVerifierPolicy(
                failureMode: .soft,
                httpClient: httpClient,
                validationTime: revocationValidationTime ?? now
            )
        case (.disabled, .disabled):
            // We should still do basic certificate validations even if expiry check is disabled
            RFC5280Policy.withValidityCheckDisabled()
        }
    }
}

/// Policy for code signing certificates.
struct _CodeSigningPolicy: VerifierPolicy {
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = [
        ASN1ObjectIdentifier.X509ExtensionID.keyUsage,
        ASN1ObjectIdentifier.X509ExtensionID.extendedKeyUsage,
    ]

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        let isCodeSigning = (
            try? chain.leaf.extensions.extendedKeyUsage?.contains(ExtendedKeyUsage.Usage.codeSigning)
        ) ??
            false
        guard isCodeSigning else {
            return .failsToMeetPolicy(reason: "Certificate \(chain.leaf) does not have code signing extended key usage")
        }
        return .meetsPolicy
    }
}

/// Policy for ADP certificates.
struct _ADPCertificatePolicy: VerifierPolicy {
    /// Include custom marker extensions (which can be critical) so they would not
    /// be considered unhandled and cause certificate chain validation to fail.
    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = Self.swiftPackageMarkers
        + Self.developmentMarkers

    // Marker extensions for Swift Package certificate
    private static let swiftPackageMarkers: [ASN1ObjectIdentifier] = [
        // This is not a critical extension but including it just in case
        ASN1ObjectIdentifier.NameAttributes.adpSwiftPackageMarker,
    ]

    // Marker extensions for Development certificate (included for testing)
    private static let developmentMarkers: [ASN1ObjectIdentifier] = [
        [1, 2, 840, 113_635, 100, 6, 1, 2],
        [1, 2, 840, 113_635, 100, 6, 1, 12],
    ]

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        // Not policing anything here. This policy is mainly for
        // listing marker extensions to prevent chain validation
        // from failing prematurely.
        .meetsPolicy
    }
}

struct _OCSPVerifierPolicy: VerifierPolicy {
    private static let cacheTTL: DispatchTimeInterval = .seconds(5 * 60)
    private let cache = ThreadSafeKeyValueStore<
        UnverifiedCertificateChain,
        (result: PolicyEvaluationResult, expires: DispatchTime)
    >()

    private var underlying: OCSPVerifierPolicy<_OCSPRequester>

    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    /// Initializes an `_OCSPVerifierPolicy` that caches its results.
    ///
    /// - Parameters:
    ///     - failureMode: `OCSPFailureMode` that defines policy failure in event of failure.
    ///                 Possible values are `hard` (OCSP request failure and unknown status
    ///                 not allowed) or `soft` (OCSP request failure and unknown status allowed).
    ///     - httpClient: `HTTPClient` that backs`_OCSPRequester` for making OCSP requests.
    ///     - validationTime: The time used to decide if the OCSP request is relatively recent. It is
    ///                   considered a failure if the request is too old.
    init(failureMode: OCSPFailureMode, httpClient: HTTPClient, validationTime: Date) {
        self.underlying = OCSPVerifierPolicy(
            failureMode: failureMode,
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
