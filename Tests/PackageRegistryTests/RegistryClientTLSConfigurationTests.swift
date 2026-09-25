//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import NIOSSL
import Testing
@testable import PackageRegistry

private let identityCertificateFile = AbsolutePath("/identity/client.cer")
private let identityPrivateKeyFile = AbsolutePath("/identity/client.key")

private let identity = RegistryConfiguration.Identity.files(
    certificatePath: identityCertificateFile.pathString,
    privateKeyPath: identityPrivateKeyFile.pathString
)

@Suite("Registry Client TLS Configuration") struct RegistryClientTLSConfigurationTests {
    @Test func presentsTheResolvedChainAndKey() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificateChainPEM,
                privateKey: material.privateKeyPEM
            )
            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(identity)

            let configuration = try resolved.makeTLSConfiguration()

            #expect(configuration.certificateChain.count == 2)
            #expect(
                configuration.certificateChain.first ==
                    .certificate(try NIOSSLCertificate(bytes: material.certificateDER, format: .der))
            )
            #expect(
                configuration.privateKey ==
                    .privateKey(try NIOSSLPrivateKey(bytes: material.privateKeyDER, format: .der))
            )
        }
    }

    @Test func keepsPlatformTrustForTheServerCertificate() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificatePEM,
                privateKey: material.privateKeyPEM
            )
            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(identity)

            let configuration = try resolved.makeTLSConfiguration()

            #expect(configuration.trustRoots == .default)
            #expect(configuration.additionalTrustRoots.isEmpty)
            #expect(configuration.certificateVerification == .fullVerification)
        }
    }
}
