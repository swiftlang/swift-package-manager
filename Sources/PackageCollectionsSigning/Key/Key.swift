/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

protocol PrivateKey {
    /// Creates a private key from PEM.
    ///
    /// - Parameters:
    ///   - pem: The key in PEM format, including the `-----BEGIN` and `-----END` lines.
    init<Data>(pem data: Data) throws where Data: DataProtocol
}

protocol PublicKey {
    /// Creates a public key from raw bytes.
    ///
    /// Refer to implementation for details on what representation the raw bytes should be.
    init(data: Data) throws

    /// Creates a public key from PEM.
    ///
    /// - Parameters:
    ///   - pem: The key in PEM format, including the `-----BEGIN` and `-----END` lines.
    init<Data>(pem data: Data) throws where Data: DataProtocol
}

enum KeyError: Error {
    case initializationFailure
    case invalidData
}

enum KeyType {
    case RSA
    case EC
}
