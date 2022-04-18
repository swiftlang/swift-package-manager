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

protocol BoringSSLKey {}

extension BoringSSLKey {
    // Source: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/Utilities/OpenSSLSigner.swift
    static func load<Data, KeyType>(pem data: Data,
                                    _ createKey: (UnsafeMutablePointer<BIO>) -> (KeyType?)) throws -> KeyType where Data: DataProtocol {
        let bytes = data.copyBytes()

        // Not doing `CCryptoBoringSSL_BIO_new_mem_buf(bytes, numericCast(bytes.count))` because
        // it causes `bioConversionFailure` error on *some* Linux builds (e.g., SPM Linux smoke test)
        let bio = CCryptoBoringSSL_BIO_new(CCryptoBoringSSL_BIO_s_mem())
        defer { CCryptoBoringSSL_BIO_free(bio) }

        guard let bioPointer = bio, CCryptoBoringSSL_BIO_write(bioPointer, bytes, numericCast(bytes.count)) > 0 else {
            throw BoringSSLKeyError.bioInitializationFailure
        }
        guard let key = createKey(bioPointer) else {
            throw BoringSSLKeyError.bioConversionFailure
        }

        return key
    }
}

enum BoringSSLKeyError: Error {
    case failedToLoadKeyFromBytes
    case rsaConversionFailure
    case bioInitializationFailure
    case bioConversionFailure
}
#endif
