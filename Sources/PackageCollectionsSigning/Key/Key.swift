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
    init(pem: String) throws
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
    init(pem: String) throws
}

enum KeyError: Error {
    case initializationFailure
    case invalidPEM
    case invalidData
}

enum KeyType {
    case RSA
    case EC
}

// MARK: - Utilities

enum KeyUtilities {
    static func stripHeaderAndFooter(pem: String) throws -> Data {
        var lines = pem.components(separatedBy: "\n").filter { line in
            !line.hasPrefix("-----BEGIN") && !line.hasPrefix("-----END")
        }

        guard !lines.isEmpty else {
            throw KeyError.invalidPEM
        }

        lines = lines.map { $0.replacingOccurrences(of: "\r", with: "") }

        guard let stripped = lines.joined(separator: "").data(using: .utf8),
            let data = Data(base64Encoded: stripped, options: [.ignoreUnknownCharacters]) else {
            throw KeyError.invalidPEM
        }

        return data
    }
}
