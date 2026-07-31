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

/// Resolves the ``Client`` a certificate stands for.
///
/// Every root CA the registry accepts names its clients differently, so
/// each ``RootCertificateAuthority`` gets its own rule for reducing a
/// certificate to the ``Client/ID`` value it was enrolled under. Keeping
/// those rules behind one entry point means request handling never has to
/// know which CA issued the certificate in hand.
///
/// Resolution is a lookup, not a trust decision: the certificate's chain and
/// the client's possession of its private key are established by the TLS
/// handshake long before the client behind it is named. An unenrolled
/// certificate resolves to `nil` — a valid certificate belonging to no
/// registered user is not an error, just an unknown client.
public struct ClientProvider: Sendable {
    let store: ClientStore

    /// Creates a provider backed by `store`.
    ///
    /// - Parameter store: The client store to resolve against.
    public init(store: ClientStore) {
        self.store = store
    }

    /// Returns the client enrolled for `certificate`.
    ///
    /// A self-signed certificate carries no issuer-assigned name that the
    /// registry could trust, so it stands for nothing beyond the exact bytes
    /// presented: its thumbprint is its client, and enrolling one is
    /// enrolling that single certificate. Reissuing it — even with the same
    /// subject and key — produces a different thumbprint and therefore a
    /// different client that must be enrolled again.
    ///
    /// - Parameters:
    ///   - certificate: The certificate presented on the request.
    ///   - rootCertificateAuthority: The root CA the certificate chains to,
    ///     which selects how the client value is derived.
    /// - Returns: The enrolled ``Client``, or `nil` if no client is
    ///   registered for `certificate`.
    /// - Throws: An `ASN1Error` if the certificate cannot be re-serialized to
    ///   compute its thumbprint.
    public func extractClient(
        from certificate: Certificate, rootCertificateAuthority: RootCertificateAuthority
    ) async throws -> Client? {
        switch rootCertificateAuthority {
        case .selfSign:
            let id = Client.ID(
                rootCertificateAuthority: .selfSign,
                value: try CertificateThumbprint.of(certificate)
            )
            return await store.client(id: id)
        }
    }
}
