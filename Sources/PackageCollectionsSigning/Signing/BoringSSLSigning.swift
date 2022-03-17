//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// This source file is part of the Vapor open source project
//
// Copyright (c) 2017-2020 Vapor project authors
// Licensed under MIT
//
// See LICENSE for license information
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

#if os(Linux) || os(Windows) || os(Android)
import Foundation

@_implementationOnly import CCryptoBoringSSL

protocol BoringSSLSigning {
    var algorithm: BoringSSLEVP { get }
}

struct BoringSSLEVP {
    let underlying: OpaquePointer

    init(type: EVPType) {
        switch type {
        case .sha256:
            self.underlying = CCryptoBoringSSL_EVP_sha256()
        }
    }

    enum EVPType {
        case sha256
    }
}

extension BoringSSLSigning {
    // Source: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/Utilities/OpenSSLSigner.swift
    func digest<Message>(_ message: Message) throws -> [UInt8] where Message: DataProtocol {
        let context = CCryptoBoringSSL_EVP_MD_CTX_new()
        defer { CCryptoBoringSSL_EVP_MD_CTX_free(context) }

        guard CCryptoBoringSSL_EVP_DigestInit_ex(context, self.algorithm.underlying, nil) == 1 else {
            throw BoringSSLSigningError.digestInitializationFailure
        }

        let message = message.copyBytes()

        guard CCryptoBoringSSL_EVP_DigestUpdate(context, message, numericCast(message.count)) == 1 else {
            throw BoringSSLSigningError.digestUpdateFailure
        }

        var digest: [UInt8] = .init(repeating: 0, count: Int(EVP_MAX_MD_SIZE))
        var digestLength: UInt32 = 0

        guard CCryptoBoringSSL_EVP_DigestFinal_ex(context, &digest, &digestLength) == 1 else {
            throw BoringSSLSigningError.digestFinalizationFailure
        }

        return .init(digest[0 ..< Int(digestLength)])
    }
}

enum BoringSSLSigningError: Error {
    case digestInitializationFailure
    case digestUpdateFailure
    case digestFinalizationFailure
}
#endif
