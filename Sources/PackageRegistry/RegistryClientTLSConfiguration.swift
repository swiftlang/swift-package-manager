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

import NIOSSL

// Input an identity, get a NIO.TLSConfiguration object back
extension RegistryClientIdentity {
    func makeTLSConfiguration() throws -> TLSConfiguration {
        switch self {
        case .files(let certificateChain, let privateKey):
            return Self.clientConfiguration(
                certificateChain: certificateChain,
                privateKey: .privateKey(privateKey)
            )
        #if os(macOS)
        case .keychain(let secIdentity):
            let identity = try KeychainTLSIdentity(secIdentity)
            return Self.clientConfiguration(
                certificateChain: identity.certificateChain,
                privateKey: .privateKey(identity.privateKey)
            )
        #endif
        }
    }

    private static func clientConfiguration(
        certificateChain: [NIOSSLCertificate],
        privateKey: NIOSSLPrivateKeySource
    ) -> TLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        configuration.certificateChain = certificateChain.map { .certificate($0) }
        configuration.privateKey = privateKey
        return configuration
    }
}
