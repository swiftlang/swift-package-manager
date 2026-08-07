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

import X509

/// A client makes authenticated requests on behalf of the user
/// Permissions are scoped to the client, not the user
public struct Client<Auth: AuthenticationMethod>: Sendable, Equatable {
    public let user: User
    public let auth: Auth

    public init(user: User, auth: Auth) {
        self.user = user
        self.auth = auth
    }
}

public protocol AuthenticationMethod: Sendable, Equatable {
    associatedtype Credentials: Sendable, Hashable
    var credentials: Credentials { get }
}

// MARK: Extensible authentication methods:

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

/// Bearer: a random token, matched by its hash.
public struct BearerAuth: AuthenticationMethod, Equatable {
    public struct Credentials: Sendable, Hashable, Equatable {
        public let tokenHash: TokenHash

        public init(tokenHash: TokenHash) {
            self.tokenHash = tokenHash
        }
    }

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

public struct MutualTLS: AuthenticationMethod, Equatable {
    public struct Credentials: Sendable, Hashable, Equatable {
        public let rootCertificateAuthority: RootCertificateAuthority
        public let id: String

        public init(rootCertificateAuthority: RootCertificateAuthority, id: String) {
            self.rootCertificateAuthority = rootCertificateAuthority
            self.id = id
        }
    }

    public let credentials: Credentials

    public init(rootCertificateAuthority: RootCertificateAuthority, id: String) {
        self.credentials = Credentials(rootCertificateAuthority: rootCertificateAuthority, id: id)
    }

    public init(rootCertificateAuthority: RootCertificateAuthority, certificate: Certificate) throws {
        switch rootCertificateAuthority {
        case .none:
            self.init(
                rootCertificateAuthority: rootCertificateAuthority,
                // Use the thumbprint of the self-signed cert to uniquely identify the client
                id: try CertificateThumbprint.of(certificate)
            )
        }
    }
}
