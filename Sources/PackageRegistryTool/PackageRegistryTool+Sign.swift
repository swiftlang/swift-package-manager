//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency

import ArgumentParser
import Basics
import CoreCommands
import PackageSigning
import TSCBasic
@_implementationOnly import X509 // FIXME: need this import or else SwiftSigningIdentity init at L128 fails

extension SwiftPackageRegistryTool {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    struct Sign: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign a package source archive"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: .init("The path to the package source archive to be signed.", valueName: "archive-path"))
        var sourceArchivePath: AbsolutePath

        @Argument(help: .init(
            "The path the output signature file will be written to.",
            valueName: "signature-output-path"
        ))
        var signaturePath: AbsolutePath

        @Option(help: .hidden) // help: "Signature format identifier. Defaults to 'cms-1.0.0'.
        var signatureFormat: SignatureFormat = .cms_1_0_0

        @Option(
            help: "The label of the signing identity to be retrieved from the system's identity store if supported."
        )
        var signingIdentity: String?

        @Option(help: "The path to the certificate's PKCS#8 private key (DER-encoded).")
        var privateKeyPath: AbsolutePath?

        @Option(
            name: .customLong("cert-chain-paths"),
            parsing: .upToNextOption,
            help: "Path(s) to the signing certificate (DER-encoded) and optionally the rest of the certificate chain. Certificates should be ordered with the leaf first and the root last."
        )
        var certificateChainPaths: [AbsolutePath] = []

        func run(_ swiftTool: SwiftTool) async throws {
            // Validate source archive path
            guard localFileSystem.exists(self.sourceArchivePath) else {
                throw StringError("Source archive not found at '\(self.sourceArchivePath)'.")
            }

            // compute signing mode
            let signingMode: PackageArchiveSigner.SigningMode
            switch (self.signingIdentity, self.certificateChainPaths, self.privateKeyPath) {
            case (.none, let certChainPaths, .none) where !certChainPaths.isEmpty:
                throw StringError(
                    "Both 'private-key-path' and 'cert-chain-paths' are required when one of them is set."
                )
            case (.none, let certChainPaths, .some) where certChainPaths.isEmpty:
                throw StringError(
                    "Both 'private-key-path' and 'cert-chain-paths' are required when one of them is set."
                )
            case (.none, let certChainPaths, .some(let privateKeyPath)) where !certChainPaths.isEmpty:
                signingMode = .certificate(certChain: certChainPaths, privateKey: privateKeyPath)
            case (.some(let signingStoreLabel), let certChainPaths, .none) where certChainPaths.isEmpty:
                signingMode = .identityStore(signingStoreLabel)
            default:
                throw StringError(
                    "Either 'signing-identity' or 'private-key-path' (together with 'cert-chain-paths') must be provided."
                )
            }

            swiftTool.observabilityScope.emit(info: "signing the archive at '\(self.sourceArchivePath)'")
            try await PackageArchiveSigner.sign(
                archivePath: self.sourceArchivePath,
                signaturePath: self.signaturePath,
                mode: signingMode,
                signatureFormat: self.signatureFormat,
                fileSystem: localFileSystem,
                observabilityScope: swiftTool.observabilityScope
            )
        }
    }
}

extension SignatureFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public enum PackageArchiveSigner {
    @discardableResult
    public static func sign(
        archivePath: AbsolutePath,
        signaturePath: AbsolutePath,
        mode: SigningMode,
        signatureFormat: SignatureFormat,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> [UInt8] {
        let archiveData = try fileSystem.readFileContents(archivePath)

        let signingIdentity: SigningIdentity
        switch mode {
        case .identityStore(let label):
            let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
            let matches = await signingIdentityStore.find(by: label)
            guard let identity = matches.first else {
                throw StringError("'\(label)' not found in the system identity store.")
            }
            // TODO: let user choose if there is more than one match?
            signingIdentity = identity
        case .certificate(let certChain, let privateKeyPath):
            guard let certificatePath = certChain.first else {
                throw StringError("No certificate path specified")
            }
            // TODO: pass the rest of cert chain to `sign`
            let certificate = try fileSystem.readFileContents(certificatePath)
            let privateKey = try fileSystem.readFileContents(privateKeyPath)
            signingIdentity = try SwiftSigningIdentity(
                derEncodedCertificate: certificate.contents,
                derEncodedPrivateKey: privateKey.contents,
                privateKeyType: signatureFormat.signingKeyType
            )
        }

        let signature = try await SignatureProvider.sign(
            content: archiveData.contents,
            identity: signingIdentity,
            format: signatureFormat,
            observabilityScope: observabilityScope
        )

        try fileSystem.writeFileContents(signaturePath) { stream in
            stream.write(signature)
        }

        return signature
    }

    public enum SigningMode {
        case identityStore(String)
        case certificate(certChain: [AbsolutePath], privateKey: AbsolutePath)
    }
}
