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
@_implementationOnly import X509

extension SignatureProviderProtocol {
    func buildPolicySet(configuration: VerifierConfiguration, httpClient: HTTPClient) -> PolicySet {
        var policies = [VerifierPolicy]()

        if case .enabled(let validationTime) = configuration.certificateExpiration {
            policies.append(RFC5280Policy(validationTime: validationTime ?? Date()))
        }

        switch configuration.certificateRevocation {
        case .strict(let validationTime):
            policies.append(_OCSPVerifierPolicy(httpClient: httpClient, mode: .strict, validationTime: validationTime))
        case .allowSoftFail(let validationTime):
            policies
                .append(_OCSPVerifierPolicy(
                    httpClient: httpClient,
                    mode: .allowSoftFail,
                    validationTime: validationTime
                ))
        case .disabled:
            ()
        }

        return PolicySet(policies: policies)
    }
}

struct _OCSPVerifierPolicy: VerifierPolicy {
    private static let cacheTTL: DispatchTimeInterval = .seconds(5 * 60)
    private let cache = ThreadSafeKeyValueStore<
        UnverifiedCertificateChain,
        (result: PolicyEvaluationResult, expires: DispatchTime)
    >()

    private let underlying: OCSPVerifierPolicy<_OCSPRequester>
    private let mode: Mode
    private let validationTime: Date

    init(httpClient: HTTPClient, mode: Mode, validationTime: Date?) {
        self.underlying = OCSPVerifierPolicy(requester: _OCSPRequester(httpClient: httpClient))
        self.mode = mode
        self.validationTime = validationTime ?? Date()
    }

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        // Check for expiration of the leaf before revocation
        let leaf = chain.leaf
        if leaf.notValidBefore > leaf.notValidAfter {
            return .failsToMeetPolicy(
                reason: "OCSPVerifierPolicy: leaf certificate \(leaf) has invalid expiry, notValidAfter is earlier than notValidBefore"
            )
        }
        if self.validationTime < leaf.notValidBefore {
            return .failsToMeetPolicy(reason: "OCSPVerifierPolicy: leaf certificate \(leaf) is not yet valid")
        }
        if self.validationTime > leaf.notValidAfter {
            return .failsToMeetPolicy(reason: "OCSPVerifierPolicy: leaf certificate \(leaf) has expired")
        }

        // Look for cached result
        if let cached = self.cache[chain], cached.expires < .now() {
            return cached.result
        }

        // This makes HTTP requests
        let result = await self.underlying.chainMeetsPolicyRequirements(chain: chain)
        let actualResult: PolicyEvaluationResult
        switch result {
        case .meetsPolicy:
            actualResult = result
        case .failsToMeetPolicy(let reason):
            switch self.mode {
            case .strict:
                actualResult = result
            case .allowSoftFail:
                // Allow 'unknown' status and failed OCSP request in this mode
                if reason.lowercased().contains("revoked through ocsp") {
                    actualResult = result
                } else {
                    actualResult = .meetsPolicy
                }
            }
        }

        // Save result to cache
        self.cache[chain] = (result: actualResult, expires: .now() + Self.cacheTTL)
        return actualResult
    }

    enum Mode {
        case strict
        case allowSoftFail
    }
}

private struct _OCSPRequester: OCSPRequester {
    let httpClient: HTTPClient

    func query(request: [UInt8], uri: String) async throws -> [UInt8] {
        guard let url = URL(string: uri), let host = url.host else {
            throw SwiftOCSPRequesterError.invalidURL(uri)
        }

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
        return Array(responseBody)
    }
}

enum SwiftOCSPRequesterError: Error {
    case invalidURL(String)
    case emptyResponse
    case invalidResponse(statusCode: Int)
}
