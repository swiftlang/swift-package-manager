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

public enum ClientStoreError: Error, Equatable, Sendable {
    case clientAlreadyExists
}

private struct AnyClient: Sendable {
    let value: any Sendable
}

public actor ClientStore {
    private var storage: [ObjectIdentifier: [AnyHashable: AnyClient]] = [:]

    func store<Auth: AuthenticationMethod>(_ client: Client<Auth>) {
        let typeKey = ObjectIdentifier(Auth.self)
        let credKey  = AnyHashable(client.auth.credentials)
        storage[typeKey, default: [:]][credKey] = AnyClient(value: client)
    }

    func client<Auth: AuthenticationMethod>(
        ofType _: Auth.Type,
        for credentials: Auth.Credentials
    ) -> Client<Auth>? {
        let typeKey = ObjectIdentifier(Auth.self)
        let credKey  = AnyHashable(credentials)
        return storage[typeKey]?[credKey]?.value as? Client<Auth>
    } 
}

