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

/// An email and password pair, verified against a bcrypt hash.
/// There can only be one ``EmailAddress`` per ``User``
public struct BasicAuth: AuthenticationMethod, Equatable {
    public struct Credentials: Sendable, Hashable, Equatable {
        public let email: EmailAddress

        public init(email: EmailAddress) {
            self.email = email
        }
    }

    public let credentials: Credentials
    public let passwordHash: String

    /// Creates a Basic authentication method for `email`.
    ///
    /// - Parameters:
    ///   - email: The owning user's normalized email, doubling as the Basic
    ///     username.
    ///   - passwordHash: A bcrypt hash of the client's password.
    public init(email: EmailAddress, passwordHash: String) {
        self.credentials = Credentials(email: email)
        self.passwordHash = passwordHash
    }
}

extension RegisteredClient where Auth == BasicAuth {
    static func basic(
        user: User,
        passwordHash: String
    ) -> Self {
        RegisteredClient(user: user, auth: BasicAuth(email: user.email, passwordHash: passwordHash))
    }
}