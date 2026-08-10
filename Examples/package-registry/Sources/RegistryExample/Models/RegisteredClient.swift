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

/// A client makes authenticated requests on behalf of the user
/// Permissions are scoped to the client, not the user
public struct RegisteredClient<Auth: AuthenticationMethod>: Sendable, Equatable {
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
