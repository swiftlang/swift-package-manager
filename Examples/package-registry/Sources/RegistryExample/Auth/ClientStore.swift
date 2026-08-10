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

/// Errors thrown by ``ClientStore/store(_:)``.
public enum ClientStoreError: Error, Equatable, Sendable {
    /// A client is already registered under the same credentials. What that
    /// means is the authentication method's choice — a second Basic client
    /// for one email, a colliding bearer token.
    case clientAlreadyExists
}

private struct AnyClient: Sendable {
    let value: any Sendable
}

public actor ClientStore {
    private var storage: [ObjectIdentifier: [AnyHashable: AnyClient]] = [:]

    public init() {}

    /// Registers `client` under its authentication method and credentials.
    ///
    /// - Parameter client: The client to persist.
    /// - Throws: ``ClientStoreError/clientAlreadyExists`` if a client is
    ///   already stored under the same method and credentials. The existing
    ///   client is left untouched.
    public func store<Auth: AuthenticationMethod>(_ client: RegisteredClient<Auth>) throws {
        let typeKey = ObjectIdentifier(Auth.self)
        let credKey  = AnyHashable(client.auth.credentials)
        guard storage[typeKey]?[credKey] == nil else {
            throw ClientStoreError.clientAlreadyExists
        }
        storage[typeKey, default: [:]][credKey] = AnyClient(value: client)
    }

    public func client<Auth: AuthenticationMethod>(
        ofType _: Auth.Type,
        for credentials: Auth.Credentials
    ) -> RegisteredClient<Auth>? {
        let typeKey = ObjectIdentifier(Auth.self)
        let credKey  = AnyHashable(credentials)
        return storage[typeKey]?[credKey]?.value as? RegisteredClient<Auth>
    }
}

