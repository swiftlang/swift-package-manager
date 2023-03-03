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
import struct Foundation.Data

import ArgumentParser
import Basics
import CoreCommands
import PackageSigning
import TSCBasic

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

        @Option(help: "The path to the signing certificate (DER-encoded).")
        var certificatePath: AbsolutePath?

        func run(_ swiftTool: SwiftTool) async throws {
            // Validate source archive path
            guard localFileSystem.exists(self.sourceArchivePath) else {
                throw StringError("Source archive not found at '\(self.sourceArchivePath)'.")
            }

            // compute signing mode
            let signingMode: PackageArchiveSigner.SigningMode
            switch (self.signingIdentity, self.certificatePath, self.privateKeyPath) {
            case (.none, .some, .none):
                throw StringError(
                    "Both 'private-key-path' and 'certificate-path' are required when one of them is set."
                )
            case (.none, .none, .some):
                throw StringError(
                    "Both 'private-key-path' and 'certificate-path' are required when one of them is set."
                )
            case (.none, .some(let certificatePath), .some(let privateKeyPath)):
                signingMode = .certificate(certificate: certificatePath, privateKey: privateKeyPath)
            case (.some(let signingStoreLabel), .none, .none):
                signingMode = .identityStore(signingStoreLabel)
            default:
                throw StringError(
                    "Either 'signing-identity' or 'private-key-path' (together with 'certificate-path') must be provided."
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
    ) async throws -> Data {
        let archiveData: Data = try fileSystem.readFileContents(archivePath)

        let signingIdentity: SigningIdentity
        switch mode {
        case .identityStore(let label):
            let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
            let matches = try await signingIdentityStore.find(by: label)
            guard let identity = matches.first else {
                throw StringError("'\(label)' not found in the system identity store.")
            }
            // TODO: let user choose if there is more than one match?
            signingIdentity = identity
        case .certificate(let certificatePath, let privateKeyPath):
            let certificateData: Data = try fileSystem.readFileContents(certificatePath)
            let privateKeyData: Data = try fileSystem.readFileContents(privateKeyPath)
            signingIdentity = SwiftSigningIdentity(
                certificate: Certificate(derEncoded: certificateData),
                privateKey: try signatureFormat.privateKey(derRepresentation: privateKeyData)
            )
        }

        let signature = try await SignatureProvider.sign(
            archiveData,
            with: signingIdentity,
            in: signatureFormat,
            observabilityScope: observabilityScope
        )

        try fileSystem.writeFileContents(signaturePath) { stream in
            stream.write(signature)
        }

        return signature
    }

    public enum SigningMode {
        case identityStore(String)
        case certificate(certificate: AbsolutePath, privateKey: AbsolutePath)
    }
}
