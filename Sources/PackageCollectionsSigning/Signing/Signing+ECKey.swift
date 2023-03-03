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

import struct Foundation.Data

// FIXME: @_implementationOnly fails on Linux
#if !os(Linux)
@_implementationOnly import Crypto
#else
import Crypto
#endif

// MARK: - MessageSigner and MessageValidator conformance

extension ECPrivateKey {
    func sign(message: Data) throws -> Data {
        let signature = try self.underlying.signature(for: SHA256.hash(data: message))
        return signature.rawRepresentation
    }
}

extension ECPublicKey {
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        return try self.underlying.isValidSignature(.init(rawRepresentation: signature), for: SHA256.hash(data: message))
    }
}
