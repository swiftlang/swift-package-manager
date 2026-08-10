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

import NIOConcurrencyHelpers
import Testing
import Vapor
@testable import RegistryExample

@Suite("ClientRegistrar")
struct ClientRegistrarTests {
    private func user(_ raw: String) throws -> User {
        User(email: try #require(EmailAddress(raw)))
    }

    private func registrar(
        _ store: ClientStore,
        mintingTokens tokens: String...
    ) -> ClientRegistrar {
        let remaining = NIOLockedValueBox(ArraySlice(tokens))
        return ClientRegistrar(
            store: store,
            tokenGenerator: TokenGenerator {
                remaining.withLockedValue { $0.popFirst() ?? "exhausted-token" }
            }
        )
    }

    // MARK: Basic

    @Test func `registering a Basic client stores it under the user's email`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let client = try await registrar(store).registerBasicClient(for: harry, password: "hunter2")

        #expect(client.user == harry)
        let stored = await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email))
        #expect(stored == client)
    }

    @Test func `a Basic client's password is stored only as a verifiable bcrypt hash`() async throws {
        let harry = try user("harry@example.com")
        let client = try await registrar(ClientStore()).registerBasicClient(for: harry, password: "hunter2")

        #expect(client.auth.passwordHash != "hunter2")
        #expect(try Bcrypt.verify("hunter2", created: client.auth.passwordHash))
    }

    @Test func `an empty password is rejected and stores nothing`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        await #expect(throws: ClientRegistrationError.emptyPassword) {
            _ = try await registrar(store).registerBasicClient(for: harry, password: "")
        }
        #expect(await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email)) == nil)
    }

    @Test func `a user cannot register a second Basic client`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        _ = try await registrar(store).registerBasicClient(for: harry, password: "hunter2")

        await #expect(throws: ClientRegistrationError.userAlreadyHasBasicClient) {
            _ = try await registrar(store).registerBasicClient(for: harry, password: "different")
        }
    }

    @Test func `a rejected second Basic client leaves the first one's password intact`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let original = try await registrar(store).registerBasicClient(for: harry, password: "hunter2")
        _ = try? await registrar(store).registerBasicClient(for: harry, password: "different")

        let stored = await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email))
        #expect(stored == original)
        #expect(try Bcrypt.verify("hunter2", created: try #require(stored).auth.passwordHash))
    }

    @Test func `different users each get their own Basic client`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let hermione = try user("hermione@example.com")
        let harrysClient = try await registrar(store).registerBasicClient(for: harry, password: "hunter2")
        let hermionesClient = try await registrar(store).registerBasicClient(for: hermione, password: "alohomora")

        #expect(
            await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email))
                == harrysClient
        )
        #expect(
            await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: hermione.email))
                == hermionesClient
        )
    }

    // MARK: Bearer

    @Test func `registering a Bearer client returns the plaintext token once and stores only its hash`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let registration = try await registrar(store, mintingTokens: "minted-token")
            .registerBearerClient(for: harry)

        #expect(registration.token == "minted-token")
        #expect(registration.client.auth.credentials.tokenHash == TokenHasher.hash("minted-token"))
        let stored = await store.client(
            ofType: BearerAuth.self,
            for: BearerAuth.Credentials(tokenHash: TokenHasher.hash("minted-token"))
        )
        #expect(stored == registration.client)
    }

    @Test func `a user can register many Bearer clients, each with its own token`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let registrar = registrar(store, mintingTokens: "laptop-token", "desktop-token")
        let laptop = try await registrar.registerBearerClient(for: harry)
        let desktop = try await registrar.registerBearerClient(for: harry)

        #expect(laptop.token != desktop.token)
        #expect(laptop.client != desktop.client)
        for registration in [laptop, desktop] {
            let credentials = BearerAuth.Credentials(tokenHash: TokenHasher.hash(registration.token))
            #expect(await store.client(ofType: BearerAuth.self, for: credentials) == registration.client)
        }
    }

    @Test func `a minted token colliding with a registered one is rejected`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let registrar = registrar(store, mintingTokens: "collision", "collision")
        _ = try await registrar.registerBearerClient(for: harry)

        await #expect(throws: ClientStoreError.clientAlreadyExists) {
            _ = try await registrar.registerBearerClient(for: harry)
        }
    }

    // MARK: Mutual TLS

    @Test func `registering a mutual TLS client stores it under the certificate's thumbprint`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let client = try await registrar(store).registerMutualTLSClient(
            for: harry,
            certificate: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .none
        )

        #expect(client.auth.credentials.id == harrysLaptopCertificate.thumbprint)
        let credentials = MutualTLS.Credentials(
            rootCertificateAuthority: .none,
            id: harrysLaptopCertificate.thumbprint
        )
        #expect(await store.client(ofType: MutualTLS.self, for: credentials) == client)
    }

    @Test func `a user can register many mutual TLS clients, one per certificate`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let registrar = registrar(store)
        let laptop = try await registrar.registerMutualTLSClient(
            for: harry,
            certificate: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .none
        )
        let desktop = try await registrar.registerMutualTLSClient(
            for: harry,
            certificate: try hermionesLaptopCertificate.certificate(),
            rootCertificateAuthority: .none
        )

        #expect(laptop != desktop)
        #expect(
            await store.client(
                ofType: MutualTLS.self,
                for: MutualTLS.Credentials(rootCertificateAuthority: .none, id: harrysLaptopCertificate.thumbprint)
            ) == laptop
        )
        #expect(
            await store.client(
                ofType: MutualTLS.self,
                for: MutualTLS.Credentials(rootCertificateAuthority: .none, id: hermionesLaptopCertificate.thumbprint)
            ) == desktop
        )
    }

    @Test func `an already-registered certificate is rejected`() async throws {
        let store = ClientStore()
        let registrar = registrar(store)
        _ = try await registrar.registerMutualTLSClient(
            for: try user("harry@example.com"),
            certificate: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .none
        )

        await #expect(throws: ClientRegistrationError.certificateAlreadyRegistered) {
            _ = try await registrar.registerMutualTLSClient(
                for: try user("hermione@example.com"),
                certificate: try harrysLaptopCertificate.certificate(),
                rootCertificateAuthority: .none
            )
        }
    }

    // MARK: Across methods

    @Test func `one user can hold a Basic, a Bearer, and a mutual TLS client at once`() async throws {
        let store = ClientStore()
        let harry = try user("harry@example.com")
        let registrar = registrar(store, mintingTokens: "minted-token")
        let basic = try await registrar.registerBasicClient(for: harry, password: "hunter2")
        let bearer = try await registrar.registerBearerClient(for: harry)
        let mutualTLS = try await registrar.registerMutualTLSClient(
            for: harry,
            certificate: try harrysLaptopCertificate.certificate(),
            rootCertificateAuthority: .none
        )

        #expect(
            await store.client(ofType: BasicAuth.self, for: BasicAuth.Credentials(email: harry.email)) == basic
        )
        #expect(
            await store.client(
                ofType: BearerAuth.self,
                for: BearerAuth.Credentials(tokenHash: TokenHasher.hash("minted-token"))
            ) == bearer.client
        )
        #expect(
            await store.client(
                ofType: MutualTLS.self,
                for: MutualTLS.Credentials(rootCertificateAuthority: .none, id: harrysLaptopCertificate.thumbprint)
            ) == mutualTLS
        )
    }
}
