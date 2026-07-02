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

/// An in-memory record of which users are currently logged in.
///
/// This registry issues no session cookie or session token, so "logged in"
/// is tracked entirely server-side: when `POST /login` succeeds the
/// authenticated user's email is recorded here. When authentication is
/// enabled (see ``configure(_:authEnabled:)``) the publish endpoint consults
/// this session — via ``RequireLoginMiddleware`` — to decide whether any
/// user is currently logged in.
///
/// State is held in memory only and is lost when the server restarts,
/// matching the reference-example scope of this server.
public actor LoginSession {
    private var loggedIn: Set<EmailAddress> = []

    /// Creates an empty session with no logged-in users.
    public init() {}

    /// Records `email` as a currently logged-in user. Logging the same user
    /// in more than once has no additional effect.
    ///
    /// - Parameter email: The normalized email of the user that just
    ///   authenticated.
    public func logIn(_ email: EmailAddress) {
        loggedIn.insert(email)
    }

    /// Whether any user is currently logged in.
    public var hasActiveUser: Bool {
        !loggedIn.isEmpty
    }

    /// Whether `email` is currently logged in.
    ///
    /// - Parameter email: The normalized email to check.
    public func isLoggedIn(_ email: EmailAddress) -> Bool {
        loggedIn.contains(email)
    }
}
