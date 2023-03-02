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

extension SwiftPackageTool {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    struct Sign: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign a package source archive"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The path to the package source archive to be signed.")
        var sourceArchivePath: AbsolutePath

        @Argument(help: "The path the output signature file will be written to.")
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

            // Check if privateKeyPath and certificatePath are set
            if self.privateKeyPath != nil {
                guard self.certificatePath != nil else {
                    throw StringError(
                        "Both 'private-key-path' and 'certificate-path' are required when one of them is set."
                    )
                }
            } else {
                guard self.certificatePath == nil else {
                    throw StringError(
                        "Both 'private-key-path' and 'certificate-path' are required when one of them is set."
                    )
                }
            }

            // Either signingIdentity or (privateKeyPath, certificatePath) is required
            guard self.signingIdentity != nil || self.privateKeyPath != nil else {
                throw StringError(
                    "Either 'signing-identity' or 'private-key-path' (together with 'certificate-path') must be provided."
                )
            }

            swiftTool.observabilityScope.emit(info: "signing the archive at '\(self.sourceArchivePath)'")
            try await PackageSigningCommand.sign(
                archivePath: self.sourceArchivePath,
                signaturePath: self.signaturePath,
                signingIdentityLabel: self.signingIdentity,
                privateKeyPath: self.privateKeyPath,
                certificatePath: self.certificatePath,
                signatureFormat: self.signatureFormat,
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

public enum PackageSigningCommand {
    @discardableResult
    public static func sign(
        archivePath: AbsolutePath,
        signaturePath: AbsolutePath,
        signingIdentityLabel: String?,
        privateKeyPath: AbsolutePath?,
        certificatePath: AbsolutePath?,
        signatureFormat: SignatureFormat,
        observabilityScope: ObservabilityScope
    ) async throws -> Data {
        let archiveData = try Data(localFileSystem.readFileContents(archivePath).contents)

        var signingIdentity: SigningIdentity?
        if let signingIdentityLabel = signingIdentityLabel {
            let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
            let matches = try await signingIdentityStore.find(by: signingIdentityLabel)
            guard !matches.isEmpty else {
                throw StringError("'\(signingIdentityLabel)' not found in the system identity store.")
            }
            // TODO: let user choose if there is more than one match?
            signingIdentity = matches.first
        } else if let privateKeyPath = privateKeyPath,
                  let certificatePath = certificatePath
        {
            let certificateData = try Data(localFileSystem.readFileContents(certificatePath).contents)
            let privateKeyData = try Data(localFileSystem.readFileContents(privateKeyPath).contents)
            signingIdentity = SwiftSigningIdentity(
                certificate: Certificate(derEncoded: certificateData),
                privateKey: try signatureFormat.privateKey(derRepresentation: privateKeyData)
            )
        }

        guard let signingIdentity = signingIdentity else {
            throw StringError("Cannot sign archive without signing identity.")
        }

        let signature = try await SignatureProvider.sign(
            archiveData,
            with: signingIdentity,
            in: signatureFormat,
            observabilityScope: observabilityScope
        )

        try localFileSystem.writeFileContents(signaturePath) { stream in
            stream.write(signature)
        }

        return signature
    }
}
