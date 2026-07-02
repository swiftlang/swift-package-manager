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
    /// Returns the lowercase hex-encoded SHA-256 of `token`.
    ///
    /// - Parameter token: The plaintext bearer token.
    /// - Returns: A 64-character lowercase hex string.
    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
