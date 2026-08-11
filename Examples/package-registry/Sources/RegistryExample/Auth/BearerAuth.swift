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

/// Bearer: a random token, matched by its hash.
public struct BearerAuth: AuthenticationMethod, Equatable {
    public struct Credentials: Sendable, Hashable, Equatable {
        public let tokenHash: TokenHash

        public init(tokenHash: TokenHash) {
            self.tokenHash = tokenHash
        }
    }

    public static let methodName = "bearer"

    public let credentials: Credentials

    /// - Parameter tokenHash: The digest of the client's bearer token.
    public init(tokenHash: TokenHash) {
        self.credentials = Credentials(tokenHash: tokenHash)
    }
    /// Creates a Bearer authentication method from a plaintext token,
    /// retaining only its hash.
    ///
    /// - Parameter token: The plaintext bearer token.
    public init(token: String) {
        self.init(tokenHash: TokenHasher.hash(token))
    }
}

extension RegisteredClient where Auth == BearerAuth {
    static func bearer(
        id: ClientID,
        user: User,
        tokenHash: TokenHash
    ) -> Self {
        RegisteredClient(id: id, user: user, auth: BearerAuth(tokenHash: tokenHash))
    }

    static func bearer(
        id: ClientID,
        user: User,
        token: String
    ) -> Self {
        RegisteredClient(id: id, user: user, auth: BearerAuth(token: token))
    }
}
