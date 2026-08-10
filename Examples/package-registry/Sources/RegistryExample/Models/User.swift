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

/// A registered account, identified solely by its ``EmailAddress``.
///
/// The registry deliberately stores nothing else about a user: no display
/// name, no profile, no timestamps, and no secrets — a credential belongs to a
/// ``RegisteredClient``, not to the account it acts for. An account is simply
/// the name that one or more clients act on behalf of, and keeping it this
/// thin is what lets a user's password, tokens, and certificates be separate
/// clients with separate permissions rather than one indivisible identity.
public struct User: Sendable, Equatable {
    /// The account's identity and lookup key.
    public let email: EmailAddress

    /// Creates a user with the given identity.
    ///
    /// - Parameter email: The normalized email identifying the account.
    public init(email: EmailAddress) {
        self.email = email
    }
}
