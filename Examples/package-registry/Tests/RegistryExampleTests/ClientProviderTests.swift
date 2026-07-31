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

import SwiftASN1
import Testing
import X509
@testable import RegistryExample

@Suite("IdentityProvider")
struct IdentityProviderTests {
    private struct TestCertificate {
        let pem: String
        let thumbprint: String

        func certificate() throws -> Certificate {
            try Certificate(pemEncoded: pem)
        }
    }

    private let harrysLaptopCertificate = TestCertificate(
        pem: """
            -----BEGIN CERTIFICATE-----
            MIIBgjCCASegAwIBAgIUUMD/N2rrlgXSBvESoeYaXD3L6CUwCgYIKoZIzj0EAwIw
            FTETMBEGA1UEAwwKaWRlbnRpdHktMTAgFw0yNjA3MzExNTA0MDNaGA8yMTI2MDcw
            NzE1MDQwM1owFTETMBEGA1UEAwwKaWRlbnRpdHktMTBZMBMGByqGSM49AgEGCCqG
            SM49AwEHA0IABEM/guBDzyQMsn1dleF9O3T6TkwWyGxtLrOjIxVXfZP9+wLbFnw9
            B0Dmo6C0wPVZXpr+Eq72t5myr7JQixOUJu2jUzBRMB0GA1UdDgQWBBRMaiXyxZUG
            Vm+jJ/NHEdAkKG+JnDAfBgNVHSMEGDAWgBRMaiXyxZUGVm+jJ/NHEdAkKG+JnDAP
            BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQDSDXL36MHnV1f/0wtx
            LWkeIYSl2h1ESSNUz3FC2XqAtAIhAKE/SiJpo8tHP04igm73t7Cc8PuyhxARgmAY
            FjWWqao8
            -----END CERTIFICATE-----
            """,
        thumbprint: "30ec37382a8099c174b534863d253345b5027f99592db88be0c3629a4a6cb798"
    )

    private let hermionesLaptopCertificate = TestCertificate(
        pem: """
            -----BEGIN CERTIFICATE-----
            MIIBgDCCASegAwIBAgIUTUXy/LZzV3wAZVOsWQ+cYXFTsN0wCgYIKoZIzj0EAwIw
            FTETMBEGA1UEAwwKaWRlbnRpdHktMjAgFw0yNjA3MzExNTA0MDNaGA8yMTI2MDcw
            NzE1MDQwM1owFTETMBEGA1UEAwwKaWRlbnRpdHktMjBZMBMGByqGSM49AgEGCCqG
            SM49AwEHA0IABJ72JAAV2i8A92yi15A89CVEnGiatpyhsE0+Bby1O1NtLTOgTQ+E
            /QUNuItI7VWRlO+FeE6rgPKSN/oL5enBovyjUzBRMB0GA1UdDgQWBBTZkaEVDkpz
            IJh8Su+ou2UgxU8p5jAfBgNVHSMEGDAWgBTZkaEVDkpzIJh8Su+ou2UgxU8p5jAP
            BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIBNflqAGnVyHhhN0S9TP
            xSPRKhRPLCaL8X+r/J/Sm4ldAiANXlxwIyYq3oPDae5/NhU4dj8rbFZ/b/CAGwQR
            nm+jGw==
            -----END CERTIFICATE-----
            """,
        thumbprint: "2ea1093834f9b724048f1c7a292856271b2244a2f4a44eb6a9aea475925af4f0"
    )

    private func user(_ raw: String) throws -> User {
        User(email: try #require(EmailAddress(raw)), credential: .password(hash: "bcrypt"))
    }

    private func identity(_ user: User, thumbprint: String) -> Identity {
        Identity(user: user, id: Identity.ID(rootCertificateAuthority: .selfSign, value: thumbprint))
    }

    @Test func `resolves the identity registered under a self-signed certificate's thumbprint`() async throws {
        let store = IdentityStore()
        let harrysLaptop = identity(try user("harry@example.com"), thumbprint: harrysLaptopCertificate.thumbprint)
        try await store.create(harrysLaptop)
        let provider = IdentityProvider(store: store)
        let extracted = try await provider.extractIdentity(
            from: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .selfSign
        )
        #expect(extracted == harrysLaptop)
    }

    @Test func `returns nil for a certificate no identity is registered under`() async throws {
        let store = IdentityStore()
        try await store.create(
            identity(try user("harry@example.com"), thumbprint: harrysLaptopCertificate.thumbprint)
        )
        let provider = IdentityProvider(store: store)
        let extracted = try await provider.extractIdentity(
            from: try hermionesLaptopCertificate.certificate(),
            rootCertificateAuthority: .selfSign
        )
        #expect(extracted == nil)
    }

    @Test func `returns nil when the store holds no identities`() async throws {
        let provider = IdentityProvider(store: IdentityStore())
        let extracted = try await provider.extractIdentity(
            from: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .selfSign
        )
        #expect(extracted == nil)
    }

    @Test func `resolves each certificate to its own user's identity`() async throws {
        let store = IdentityStore()
        let harrysLaptop = identity(try user("harry@example.com"), thumbprint: harrysLaptopCertificate.thumbprint)
        let hermionesLaptop = identity(
            try user("hermione@example.com"),
            thumbprint: hermionesLaptopCertificate.thumbprint
        )
        try await store.create(harrysLaptop)
        try await store.create(hermionesLaptop)
        let provider = IdentityProvider(store: store)
        #expect(
            try await provider.extractIdentity(
                from: try harrysLaptopCertificate.certificate(),
                rootCertificateAuthority: .selfSign
            ) == harrysLaptop
        )
        #expect(
            try await provider.extractIdentity(
                from: try hermionesLaptopCertificate.certificate(),
                rootCertificateAuthority: .selfSign
            ) == hermionesLaptop
        )
    }

    @Test func `the same certificate resolves the same identity on every request`() async throws {
        let store = IdentityStore()
        let harrysLaptop = identity(try user("harry@example.com"), thumbprint: harrysLaptopCertificate.thumbprint)
        try await store.create(harrysLaptop)
        let provider = IdentityProvider(store: store)
        let first = try await provider.extractIdentity(
            from: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .selfSign
        )
        let second = try await provider.extractIdentity(
            from: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .selfSign
        )
        #expect(first == harrysLaptop)
        #expect(second == harrysLaptop)
    }
}
