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

/// A registered account, identified solely by its ``EmailAddress`` and
/// holding exactly one authentication credential.
///
/// The registry deliberately stores nothing else about a user: no display
/// name, no profile, no timestamps. This keeps the example focused on the
/// two credential shapes SwiftPM's registry login supports — HTTP Basic
/// (a password) and Bearer (a token).
///
/// Only *hashes* are retained. A password is stored as a bcrypt hash and a
/// token as the hex-encoded SHA-256 of the plaintext, so the value that a
/// client presents at login can be verified without the server ever
/// persisting the secret itself.
public struct User: Sendable, Equatable {
    /// The account's identity and lookup key.
    public let email: EmailAddress

    /// Creates a user with the given identity and credential.
    ///
    /// - Parameters:
    ///   - email: The normalized email identifying the account.
    ///   - credential: The hashed credential used to authenticate.
    public init(email: EmailAddress) {
        self.email = email
    }
}
