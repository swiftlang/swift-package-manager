//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import CryptoKit

/// The hex-encoded SHA-256 of a bearer token: the stored form of a token
/// credential and the key of the ``UserStore``'s token index.
///
/// Wrapping the digest in a dedicated type instead of passing a bare `String`
/// gives the compiler something to enforce: an ``EmailAddress``, a plaintext
/// token, a bcrypt password hash, or any other string can no longer be handed
/// to ``UserStore/user(tokenHash:)`` by mistake. A value is only ever produced
/// by ``TokenHasher/hash(_:)``, so holding a `TokenHash` is itself proof that
/// it is a real token digest.
public struct TokenHash: Hashable, Sendable {
    /// The 64-character lowercase hex string.
    let value: String

    fileprivate init(value: String) {
        self.value = value
    }
}

/// Hashes bearer tokens for storage and lookup.
///
/// Tokens are high-entropy secrets, so an unsalted, fast digest is both
/// sufficient and desirable: it is deterministic, which lets the store key
/// its token index by the hash and resolve a presented token in one
/// lookup. The encoding — lowercase hex of a SHA-256 digest — matches the
/// source-archive checksum convention already used elsewhere in the
/// registry, so all hashes in the codebase read the same way.
///
/// Registration and login MUST hash through this single entry point so the
/// stored key and the lookup key are always byte-identical.
enum TokenHasher {
    /// Returns the ``TokenHash`` — lowercase hex-encoded SHA-256 — of `token`.
    ///
    /// - Parameter token: The plaintext bearer token.
    /// - Returns: The token's digest, wrapped in a ``TokenHash``.
    static func hash(_ token: String) -> TokenHash {
        let hex = SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return TokenHash(value: hex)
    }
}
