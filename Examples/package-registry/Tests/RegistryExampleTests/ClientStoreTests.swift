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

import Testing
@testable import RegistryExample

@Suite("IdentityStore")
struct IdentityStoreTests {
    private func user(_ raw: String) throws -> User {
        User(email: try #require(EmailAddress(raw)), credential: .password(hash: "bcrypt"))
    }

    private func identity(_ user: User, _ value: String) -> Identity {
        Identity(user: user, id: Identity.ID(rootCertificateAuthority: .selfSign, value: value))
    }

    @Test func `round-trips an identity by its ID`() async throws {
        let store = IdentityStore()
        let certificateThumbprint1 = identity(try user("harry@example.com"), "certificate thumbprint 1")
        try await store.create(certificateThumbprint1)
        #expect(await store.identity(id: certificateThumbprint1.id) == certificateThumbprint1)
    }

    @Test func `returns every identity belonging to a user`() async throws {
        let store = IdentityStore()
        let harry = try user("harry@example.com")
        let certificateThumbprint1 = identity(harry, "certificate thumbprint 1")
        let certificateThumbprint2 = identity(harry, "certificate thumbprint 2")
        try await store.create(certificateThumbprint1)
        try await store.create(certificateThumbprint2)
        #expect(await store.allIdentities(for: harry.email) == [certificateThumbprint1, certificateThumbprint2])
    }

    @Test func `scopes identities to their own user`() async throws {
        let store = IdentityStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysCertificateThumbprint = identity(harry, "certificate thumbprint 1")
        try await store.create(harrysCertificateThumbprint)
        try await store.create(identity(hermione, "certificate thumbprint 2"))
        #expect(await store.allIdentities(for: harry.email) == [harrysCertificateThumbprint])
    }

    @Test func `duplicate ID throws identityAlreadyExists`() async throws {
        let store = IdentityStore()
        let harry = try user("harry@example.com")
        try await store.create(identity(harry, "certificate thumbprint 1"))
        await #expect(throws: IdentityStoreError.identityAlreadyExists) {
            try await store.create(identity(harry, "certificate thumbprint 1"))
        }
    }

    @Test func `duplicate ID leaves no partial state`() async throws {
        let store = IdentityStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysCertificateThumbprint = identity(harry, "certificate thumbprint 1")
        try await store.create(harrysCertificateThumbprint)
        await #expect(throws: IdentityStoreError.identityAlreadyExists) {
            try await store.create(identity(hermione, "certificate thumbprint 1"))
        }
        #expect(await store.allIdentities(for: hermione.email).isEmpty)
        #expect(await store.identity(id: harrysCertificateThumbprint.id) == harrysCertificateThumbprint)
    }

    @Test func `unknown ID returns nil`() async throws {
        let store = IdentityStore()
        let unknown = Identity.ID(rootCertificateAuthority: .selfSign, value: "missing")
        #expect(await store.identity(id: unknown) == nil)
    }

    @Test func `user with no identities returns an empty array`() async throws {
        let store = IdentityStore()
        #expect(await store.allIdentities(for: try user("voldemort@example.com").email).isEmpty)
    }

    @Test func `the application caches a single store across accesses`() async throws {
        try await withRegistryApp { app in
            let certificateThumbprint1 = identity(try user("harry@example.com"), "certificate thumbprint 1")
            try await app.identityStore.create(certificateThumbprint1)
            #expect(await app.identityStore.identity(id: certificateThumbprint1.id) == certificateThumbprint1)
        }
    }
}
