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
        case .strict:
            policies.append(_OCSPVerifierPolicy(httpClient: httpClient, mode: .strict))
        case .allowSoftFail:
            policies.append(_OCSPVerifierPolicy(httpClient: httpClient, mode: .allowSoftFail))
        case .disabled:
            ()
        }

        return PolicySet(policies: policies)
    }
}

struct _OCSPVerifierPolicy: VerifierPolicy {
    private let underlying: OCSPVerifierPolicy<_OCSPRequester>
    private let mode: Mode

    init(httpClient: HTTPClient, mode: Mode) {
        self.underlying = OCSPVerifierPolicy(requester: _OCSPRequester(httpClient: httpClient))
        self.mode = mode
    }

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        let result = await self.underlying.chainMeetsPolicyRequirements(chain: chain)
        switch result {
        case .meetsPolicy:
            return result
        case .failsToMeetPolicy(let reason):
            switch self.mode {
            case .strict:
                return result
            case .allowSoftFail:
                // Allow 'unknown' status and failed OCSP request in this mode
                guard !reason.lowercased().contains("revoked through ocsp") else {
                    return result
                }
                return .meetsPolicy
            }
        }
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
