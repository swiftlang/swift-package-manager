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

import struct Foundation.Data

protocol MessageSigner {
    /// Signs a message.
    ///
    /// - Returns:The message's signature.
    ///
    /// - Parameters:
    ///   - message: The message to sign.
    func sign(message: Data) throws -> Data
}

protocol MessageValidator {
    /// Checks if a signature is valid for a message.
    ///
    /// - Parameters:
    ///   - signature: The signature to verify.
    ///   - message: The message to check signature for.
    func isValidSignature(_ signature: Data, for message: Data) throws -> Bool
}

enum SigningError: Error {
    case signFailure
    case algorithmFailure
}
