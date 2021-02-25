/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Data

#if os(macOS)
import Security
#endif

// MARK: - MessageSigner and MessageValidator conformance using the Security framework

#if os(macOS)
extension CoreRSAPrivateKey {
    func sign(message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(self.underlying,
                                                    .rsaSignatureMessagePKCS1v15SHA256,
                                                    message as CFData,
                                                    &error) as Data? else {
            throw error.map { $0.takeRetainedValue() as Error } ?? SigningError.signFailure
        }
        return signature
    }
}

extension CoreRSAPublicKey {
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        SecKeyVerifySignature(
            self.underlying,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            signature as CFData,
            nil // no-match is considered an error as well so we would rather not trap it
        )
    }
}

// MARK: - MessageSigner and MessageValidator conformance using BoringSSL

#else
extension BoringSSLRSAPrivateKey {
    func sign(message: Data) throws -> Data {
        fatalError("Not implemented: \(#function)")
    }
}

extension BoringSSLRSAPublicKey {
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        fatalError("Not implemented: \(#function)")
    }
}
#endif
