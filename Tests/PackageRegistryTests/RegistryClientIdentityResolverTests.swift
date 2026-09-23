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

private let certificateFile = AbsolutePath("/identity/client.cer")
private let privateKeyFile = AbsolutePath("/identity/client.key")

private let filesIdentity = RegistryConfiguration.Identity.files(
    certificatePath: certificateFile.pathString,
    privateKeyPath: privateKeyFile.pathString
)

@Suite("Registry Client Identity Resolver") struct RegistryClientIdentityResolverTests {
    @Test func resolvesPEMCertificateAndKey() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificatePEM,
                privateKey: material.privateKeyPEM
            )

            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(filesIdentity)

            guard case .files(let certificateChain, let privateKey) = resolved else {
                Issue.record("expected a file-based identity")
                return
            }

            #expect(certificateChain.count == 1)
            #expect(try certificateChain.first?.toDERBytes() == material.certificateDER)
            #expect(privateKey == (try NIOSSLPrivateKey(bytes: material.privateKeyDER, format: .der)))
        }
    }

    @Test func resolvesPEMCertificateChain() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificateChainPEM,
                privateKey: material.privateKeyPEM
            )

            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(filesIdentity)

            guard case .files(let certificateChain, _) = resolved else {
                Issue.record("expected a file-based identity")
                return
            }

            #expect(certificateChain.count == 2)
            #expect(try certificateChain.first?.toDERBytes() == material.certificateDER)
        }
    }

    @Test func resolvesDERCertificateAndKey() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificateDER,
                privateKey: material.privateKeyDER
            )

            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(filesIdentity)

            guard case .files(let certificateChain, _) = resolved else {
                Issue.record("expected a file-based identity")
                return
            }

            #expect(try certificateChain.first?.toDERBytes() == material.certificateDER)
        }
    }

    @Test func resolvesPEMWithBagAttributesPreamble() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let preambled = material.preambledPEM()
            let fileSystem = try material.fileSystem(
                certificate: preambled.certificate,
                privateKey: preambled.privateKey
            )

            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(filesIdentity)

            guard case .files(let certificateChain, _) = resolved else {
                Issue.record("expected a file-based identity")
                return
            }

            #expect(try certificateChain.first?.toDERBytes() == material.certificateDER)
        }
    }

    @Test func resolvesPEMWithLeadingNewline() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let newline = Array("\n".utf8)
            let fileSystem = try material.fileSystem(
                certificate: newline + material.certificatePEM,
                privateKey: newline + material.privateKeyPEM
            )

            let resolved = try RegistryClientIdentityResolver(fileSystem: fileSystem).resolve(filesIdentity)

            guard case .files(let certificateChain, _) = resolved else {
                Issue.record("expected a file-based identity")
                return
            }

            #expect(try certificateChain.first?.toDERBytes() == material.certificateDER)
        }
    }

    @Test func reportsMissingCertificateFile() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = InMemoryFileSystem()
            try fileSystem.createDirectory(privateKeyFile.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(privateKeyFile, data: Data(material.privateKeyPEM))

            let resolver = RegistryClientIdentityResolver(fileSystem: fileSystem)

            #expect {
                try resolver.resolve(filesIdentity)
            } throws: { error in
                guard case RegistryClientIdentityError.missingFile(let path) = error else { return false }
                return path == certificateFile.pathString
            }
        }
    }

    @Test func reportsMissingPrivateKeyFile() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = InMemoryFileSystem()
            try fileSystem.createDirectory(certificateFile.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(certificateFile, data: Data(material.certificatePEM))

            let resolver = RegistryClientIdentityResolver(fileSystem: fileSystem)

            #expect {
                try resolver.resolve(filesIdentity)
            } throws: { error in
                guard case RegistryClientIdentityError.missingFile(let path) = error else { return false }
                return path == privateKeyFile.pathString
            }
        }
    }

    @Test func reportsUnparsableCertificate() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: Array("not a certificate".utf8),
                privateKey: material.privateKeyPEM
            )

            let resolver = RegistryClientIdentityResolver(fileSystem: fileSystem)

            #expect {
                try resolver.resolve(filesIdentity)
            } throws: { error in
                guard case RegistryClientIdentityError.invalidCertificate(let path, _) = error else { return false }
                return path == certificateFile.pathString
            }
        }
    }

    @Test func reportsUnparsablePrivateKey() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await IdentityMaterial.make(in: directory)
            let fileSystem = try material.fileSystem(
                certificate: material.certificatePEM,
                privateKey: Array("-----BEGIN PRIVATE KEY-----\nnope\n-----END PRIVATE KEY-----\n".utf8)
            )

            let resolver = RegistryClientIdentityResolver(fileSystem: fileSystem)

            #expect {
                try resolver.resolve(filesIdentity)
            } throws: { error in
                guard case RegistryClientIdentityError.invalidPrivateKey(let path, _) = error else { return false }
                return path == privateKeyFile.pathString
            }
        }
    }

    #if os(macOS)
    @Test func reportsCommonNameConflictForAmbiguousKeychainIdentities() throws {
        let first = KeychainIdentityAttributes(commonName: "client.example.com", hash: "AAAA")
        let second = KeychainIdentityAttributes(commonName: "client.example.com", hash: "BBBB")

        #expect {
            try RegistryClientIdentityResolver.keychainIdentity(
                from: .ambiguous([first, second]),
                commonName: "client.example.com",
                hash: first.hash
            )
        } throws: { error in
            guard case RegistryClientIdentityError.commonNameConflict(let name, let hashes) = error else {
                return false
            }
            return name == "client.example.com" && hashes == [first.hash, second.hash]
        }
    }
    #endif
}

struct IdentityMaterial {
    let certificatePEM: [UInt8]
    let certificateChainPEM: [UInt8]
    let certificateDER: [UInt8]
    let privateKeyPEM: [UInt8]
    let privateKeyDER: [UInt8]

    static func make(in directory: AbsolutePath) async throws -> IdentityMaterial {
        try await openssl(
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
            "-subj", "/CN=client.example.com",
            "-keyout", directory.appending("client.key.pem").pathString,
            "-out", directory.appending("client.cer.pem").pathString
        )
        try await openssl(
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
            "-subj", "/CN=intermediate.example.com",
            "-keyout", directory.appending("intermediate.key.pem").pathString,
            "-out", directory.appending("intermediate.cer.pem").pathString
        )
        try await openssl(
            "x509", "-outform", "der",
            "-in", directory.appending("client.cer.pem").pathString,
            "-out", directory.appending("client.cer.der").pathString
        )
        try await openssl(
            "rsa", "-outform", "der",
            "-in", directory.appending("client.key.pem").pathString,
            "-out", directory.appending("client.key.der").pathString
        )

        let certificatePEM = try bytes(at: directory.appending("client.cer.pem"))
        let intermediatePEM = try bytes(at: directory.appending("intermediate.cer.pem"))

        return IdentityMaterial(
            certificatePEM: certificatePEM,
            certificateChainPEM: certificatePEM + intermediatePEM,
            certificateDER: try bytes(at: directory.appending("client.cer.der")),
            privateKeyPEM: try bytes(at: directory.appending("client.key.pem")),
            privateKeyDER: try bytes(at: directory.appending("client.key.der"))
        )
    }

    func fileSystem(certificate: [UInt8], privateKey: [UInt8]) throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.createDirectory(certificateFile.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(certificateFile, data: Data(certificate))
        try fileSystem.writeFileContents(privateKeyFile, data: Data(privateKey))
        return fileSystem
    }

    func preambledPEM() -> (certificate: [UInt8], privateKey: [UInt8]) {
        let preamble = Array("""
        Bag Attributes
            friendlyName: client
            localKeyID: 01 02 03
        subject=CN=client.example.com
        issuer=CN=client.example.com

        """.utf8)

        return (
            certificate: preamble + self.certificatePEM,
            privateKey: preamble + self.privateKeyPEM
        )
    }

    static func bytes(at path: AbsolutePath) throws -> [UInt8] {
        [UInt8](try localFileSystem.readFileContents(path) as Data)
    }

    static func openssl(_ arguments: String...) async throws {
        try await AsyncProcess.checkNonZeroExit(arguments: ["openssl"] + arguments)
    }
}
