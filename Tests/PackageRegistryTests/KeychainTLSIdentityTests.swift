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

#if os(macOS)
import Basics
import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import Security
import Testing
@testable import PackageRegistry

@Suite("Keychain TLS Identity", .serialized) struct KeychainTLSIdentityTests {
    @Test func presentsTheLeafCertificateAndACustomPrivateKey() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.rsa(in: directory)

            let configuration = try RegistryClientIdentity.keychain(material.identity).makeTLSConfiguration()

            #expect(
                configuration.certificateChain ==
                    [.certificate(try NIOSSLCertificate(bytes: material.certificateDER, format: .der))]
            )
            #expect(configuration.privateKey != nil)
            #expect(configuration.trustRoots == .default)
        }
    }

    @Test func presentsTheIntermediateThatIssuedTheLeaf() async throws {
        try await withTemporaryDirectory { directory in
            let issued = try await IssuedKeychainIdentity.make(in: directory)

            let identity = try KeychainTLSIdentity(issued.leaf.identity, issuers: [issued.intermediate])

            #expect(identity.certificateChain == [
                try NIOSSLCertificate(bytes: issued.leaf.certificateDER, format: .der),
                try NIOSSLCertificate(bytes: IssuedKeychainIdentity.der(of: issued.intermediate), format: .der),
            ])
        }
    }

    @Test func leavesTheRootOutOfThePresentedChain() async throws {
        try await withTemporaryDirectory { directory in
            let issued = try await IssuedKeychainIdentity.make(in: directory)

            let identity = try KeychainTLSIdentity(
                issued.leaf.identity,
                issuers: [issued.intermediate, issued.root]
            )

            #expect(identity.certificateChain == [
                try NIOSSLCertificate(bytes: issued.leaf.certificateDER, format: .der),
                try NIOSSLCertificate(bytes: IssuedKeychainIdentity.der(of: issued.intermediate), format: .der),
            ])
        }
    }

    @Test func advertisesRSASignatureAlgorithms() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.rsa(in: directory)

            let algorithms = try KeychainSigningKey(material.privateKey).signatureAlgorithms

            #expect(Set(algorithms) == Set([
                .rsaPssRsaeSha256, .rsaPssRsaeSha384, .rsaPssRsaeSha512,
                .rsaPkcs1Sha256, .rsaPkcs1Sha384, .rsaPkcs1Sha512,
            ]))
        }
    }

    @Test func advertisesOnlyTheCurveTheKeyUses() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.ellipticCurve(in: directory)

            let algorithms = try KeychainSigningKey(material.privateKey).signatureAlgorithms

            #expect(algorithms == [.ecdsaSecp256R1Sha256])
        }
    }

    @Test(arguments: [
        SignatureAlgorithm.rsaPkcs1Sha256,
        .rsaPkcs1Sha384,
        .rsaPkcs1Sha512,
        .rsaPssRsaeSha256,
        .rsaPssRsaeSha384,
        .rsaPssRsaeSha512,
    ])
    func producesAVerifiableRSASignature(algorithm: SignatureAlgorithm) async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.rsa(in: directory)

            try await Self.expectVerifiableSignature(material: material, algorithm: algorithm)
        }
    }

    @Test func producesAVerifiableECDSASignature() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.ellipticCurve(in: directory)

            try await Self.expectVerifiableSignature(material: material, algorithm: .ecdsaSecp256R1Sha256)
        }
    }

    @Test func refusesAnAlgorithmTheKeyCannotProduce() async throws {
        try await withTemporaryDirectory { directory in
            let material = try await KeychainIdentityMaterial.rsa(in: directory)
            let key = try KeychainSigningKey(material.privateKey)

            await #expect {
                try await key.sign(
                    on: NIOSingletons.posixEventLoopGroup.any(),
                    algorithm: .ecdsaSecp256R1Sha256,
                    data: ByteBuffer(string: "payload")
                ).get()
            } throws: { error in
                guard case KeychainTLSIdentityError.unsupportedSignatureAlgorithm = error else { return false }
                return true
            }
        }
    }

    private static let payload = Data("swift package registry mutual TLS".utf8)

    private static func expectVerifiableSignature(
        material: KeychainIdentityMaterial,
        algorithm: SignatureAlgorithm
    ) async throws {
        let key = try KeychainSigningKey(material.privateKey)

        let signature = try await key.sign(
            on: NIOSingletons.posixEventLoopGroup.any(),
            algorithm: algorithm,
            data: ByteBuffer(bytes: Self.payload)
        ).get()

        let publicKey = try #require(SecKeyCopyPublicKey(material.privateKey))
        let verification = try #require(Self.verificationAlgorithms[algorithm])
        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            verification,
            Self.payload as CFData,
            Data(signature.readableBytesView) as CFData,
            &error
        )
        #expect(verified, "\(String(describing: error?.takeRetainedValue()))")
    }

    private static let verificationAlgorithms: [SignatureAlgorithm: SecKeyAlgorithm] = [
        .rsaPkcs1Sha256: .rsaSignatureMessagePKCS1v15SHA256,
        .rsaPkcs1Sha384: .rsaSignatureMessagePKCS1v15SHA384,
        .rsaPkcs1Sha512: .rsaSignatureMessagePKCS1v15SHA512,
        .rsaPssRsaeSha256: .rsaSignatureMessagePSSSHA256,
        .rsaPssRsaeSha384: .rsaSignatureMessagePSSSHA384,
        .rsaPssRsaeSha512: .rsaSignatureMessagePSSSHA512,
        .ecdsaSecp256R1Sha256: .ecdsaSignatureMessageX962SHA256,
    ]
}

struct KeychainIdentityMaterial {
    let identity: SecIdentity
    let certificateDER: [UInt8]
    let privateKey: SecKey

    static func rsa(in directory: AbsolutePath) async throws -> KeychainIdentityMaterial {
        try await IdentityMaterial.openssl(
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
            "-subj", "/CN=client.example.com",
            "-keyout", directory.appending("client.key").pathString,
            "-out", directory.appending("client.cer").pathString
        )
        return try await Self.bundle(in: directory)
    }

    static func ellipticCurve(in directory: AbsolutePath) async throws -> KeychainIdentityMaterial {
        try await IdentityMaterial.openssl(
            "ecparam", "-name", "prime256v1", "-genkey", "-noout",
            "-out", directory.appending("client.key").pathString
        )
        try await IdentityMaterial.openssl(
            "req", "-x509", "-new", "-days", "30",
            "-subj", "/CN=client.example.com",
            "-key", directory.appending("client.key").pathString,
            "-out", directory.appending("client.cer").pathString
        )
        return try await Self.bundle(in: directory)
    }

    fileprivate static func bundle(in directory: AbsolutePath) async throws -> KeychainIdentityMaterial {
        let bundlePath = directory.appending("client.p12")
        try await IdentityMaterial.openssl(
            "pkcs12", "-export",
            "-inkey", directory.appending("client.key").pathString,
            "-in", directory.appending("client.cer").pathString,
            "-out", bundlePath.pathString,
            "-passout", "pass:swiftpm"
        )

        let bundle = try localFileSystem.readFileContents(bundlePath) as Data
        var imported: CFArray?
        let status = SecPKCS12Import(
            bundle as CFData,
            [kSecImportExportPassphrase as String: "swiftpm"] as CFDictionary,
            &imported
        )
        try #require(status == errSecSuccess, "SecPKCS12Import failed with \(status)")

        let items = try #require(imported as? [[String: Any]])
        let identity = try #require(items.first?[kSecImportItemIdentity as String]) as! SecIdentity

        var certificate: SecCertificate?
        try #require(SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess)
        var privateKey: SecKey?
        try #require(SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess)

        return KeychainIdentityMaterial(
            identity: identity,
            certificateDER: [UInt8](SecCertificateCopyData(try #require(certificate)) as Data),
            privateKey: try #require(privateKey)
        )
    }
}

struct IssuedKeychainIdentity {
    let leaf: KeychainIdentityMaterial
    let intermediate: SecCertificate
    let root: SecCertificate

    static func make(in directory: AbsolutePath) async throws -> IssuedKeychainIdentity {
        try await IdentityMaterial.openssl(
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
            "-subj", "/CN=root.chain.example.com",
            "-keyout", directory.appending("root.key").pathString,
            "-out", directory.appending("root.cer").pathString
        )
        try await Self.issue(
            "intermediate",
            by: "root",
            extensions: "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n",
            in: directory
        )
        try await Self.issue(
            "client",
            by: "intermediate",
            extensions: "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n",
            in: directory
        )

        return IssuedKeychainIdentity(
            leaf: try await KeychainIdentityMaterial.bundle(in: directory),
            intermediate: try Self.certificate(at: directory.appending("intermediate.cer")),
            root: try Self.certificate(at: directory.appending("root.cer"))
        )
    }

    static func der(of certificate: SecCertificate) -> [UInt8] {
        [UInt8](SecCertificateCopyData(certificate) as Data)
    }

    private static func issue(
        _ name: String,
        by issuer: String,
        extensions: String,
        in directory: AbsolutePath
    ) async throws {
        let extensionsFile = directory.appending("\(name).ext")
        try localFileSystem.writeFileContents(extensionsFile, string: extensions)
        try await IdentityMaterial.openssl(
            "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-subj", "/CN=\(name).chain.example.com",
            "-keyout", directory.appending("\(name).key").pathString,
            "-out", directory.appending("\(name).csr").pathString
        )
        try await IdentityMaterial.openssl(
            "x509", "-req", "-days", "30", "-CAcreateserial",
            "-in", directory.appending("\(name).csr").pathString,
            "-CA", directory.appending("\(issuer).cer").pathString,
            "-CAkey", directory.appending("\(issuer).key").pathString,
            "-extfile", extensionsFile.pathString,
            "-out", directory.appending("\(name).cer").pathString
        )
    }

    private static func certificate(at path: AbsolutePath) throws -> SecCertificate {
        let der = try #require(try NIOSSLCertificate.fromPEMFile(path.pathString).first).toDERBytes()
        return try #require(SecCertificateCreateWithData(nil, Data(der) as CFData))
    }
}
#endif
