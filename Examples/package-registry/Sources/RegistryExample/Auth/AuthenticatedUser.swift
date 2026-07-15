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

import Vapor

/// The identity established once a request's credentials verify.
///
/// ``UserAuthenticator``, acting as an `AsyncRequestAuthenticator`
/// middleware, logs a value of this type into `request.auth` after
/// validating the presented credentials. Downstream handlers retrieve it
/// with `request.auth.require(AuthenticatedUser.self)`.
///
/// Like ``User``, the registry keeps nothing here but the account's
/// ``EmailAddress`` — the request has already been authenticated, so the
/// credential material is neither needed nor retained.
public struct AuthenticatedUser: Authenticatable, Sendable, Equatable {
    /// The normalized email identifying the authenticated account.
    public let email: EmailAddress

    /// Creates an authenticated user identified by `email`.
    ///
    /// - Parameter email: The verified account's normalized email.
    public init(email: EmailAddress) {
        self.email = email
    }
}
