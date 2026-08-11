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

/// What can be said about a ``RegisteredClient`` without saying anything
/// secret.
///
/// A summary is safe to serialize, log, and hand back to a caller, because 
/// a password hash or ``TokenHash`` cannot travel inside one.
public struct ClientSummary: Sendable, Equatable {
    /// The client's public name.
    public let id: ClientID
    /// The account the client acts for.
    public let user: User
    /// The name of the authentication method that verifies the client, for
    /// example `"bearer"`.
    public let method: String

    /// Creates a summary of a registered client.
    ///
    /// - Parameters:
    ///   - id: The client's public name.
    ///   - user: The account the client acts for.
    ///   - method: The name of the client's authentication method.
    public init(id: ClientID, user: User, method: String) {
        self.id = id
        self.user = user
        self.method = method
    }
}

extension RegisteredClient {
    /// The credential-free description of this client.
    var summary: ClientSummary {
        ClientSummary(id: id, user: user, method: Auth.methodName)
    }
}
