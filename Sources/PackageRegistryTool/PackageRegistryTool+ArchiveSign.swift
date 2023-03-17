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

import ArgumentParser
import Basics
import Commands
import CoreCommands
import PackageModel
import PackageSigning
import TSCBasic
import struct TSCUtility.Version
import Workspace
@_implementationOnly import X509 // FIXME: need this import or else SwiftSigningIdentity init at L139 fails

import struct Foundation.Data

extension SwiftPackageRegistryTool {
    struct ArchiveSign: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Generate and sign a package source archive"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: .init("The package identifier.", valueName: "package-id"))
        var packageIdentity: PackageIdentity

        @Argument(help: .init("The package release version being created.", valueName: "package-version"))
        var packageVersion: Version

        @Argument(help: .init(
            "The path of the directory where the source archive and signature file will be written."
        ))
        var outputDirectory: AbsolutePath

        @Option(
            name: .customLong("scratch-directory"),
            help: "The path of the directory where working file(s) will be written."
        )
        var customWorkingDirectory: AbsolutePath?

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

        func run(_ swiftTool: SwiftTool) throws {
            // validate package location
            let packageDirectory = try self.globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
            guard localFileSystem.isDirectory(packageDirectory) else {
                throw StringError("No package found at '\(packageDirectory)'.")
            }

            // validate output directory path
            guard localFileSystem.isDirectory(self.outputDirectory) else {
                throw StringError("Directory not found at '\(self.outputDirectory)'.")
            }

            // validate working directory path
            if let customWorkingDirectory = self.customWorkingDirectory {
                guard localFileSystem.isDirectory(customWorkingDirectory) else {
                    throw StringError("Directory not found at '\(customWorkingDirectory)'.")
                }
            }

            let workingDirectory = self.customWorkingDirectory ?? Workspace.DefaultLocations
                .scratchDirectory(forRootPackage: packageDirectory).appending(components: ["registry", "publish"])
            if localFileSystem.exists(workingDirectory) {
                try localFileSystem.removeFileTree(workingDirectory)
            }

            // compute signing mode
            let signingMode = try PackageArchiveSigner.computeSigningMode(
                signingIdentity: self.signingIdentity,
                privateKeyPath: self.privateKeyPath,
                certificateChainPaths: self.certificateChainPaths
            )

            // archive and sign
            let result = try PackageArchiveSigner.prepareArchiveAndSign(
                packageIdentity: self.packageIdentity,
                packageVersion: self.packageVersion,
                packageDirectory: packageDirectory,
                metadataPath: .none,
                workingDirectory: workingDirectory,
                mode: signingMode,
                signatureFormat: self.signatureFormat,
                cancellator: swiftTool.cancellator,
                fileSystem: localFileSystem,
                observabilityScope: swiftTool.observabilityScope
            )

            let archivePath = outputDirectory.appending("\(packageIdentity)-\(packageVersion).zip")
            swiftTool.observabilityScope.emit(info: "writing archive to '\(archivePath)'")
            try localFileSystem.copy(from: result.archive.path, to: archivePath)

            let signaturePath = outputDirectory.appending("\(packageIdentity)-\(packageVersion).sig")
            swiftTool.observabilityScope.emit(info: "writing archive signature to '\(signaturePath)'")
            try localFileSystem.writeFileContents(signaturePath, bytes: .init(result.archive.signature))
        }
    }
}

extension SignatureFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

enum PackageArchiveSigner {
    static func prepareArchiveAndSign(
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageDirectory: AbsolutePath,
        metadataPath: AbsolutePath?,
        workingDirectory: AbsolutePath,
        mode: SigningMode,
        signatureFormat: SignatureFormat,
        cancellator: Cancellator?,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> ArchiveAndSignResult {
        // signing identity
        let (signingIdentity, intermediateCertificates) = try Self.signingIdentityAndIntermediateCertificates(
            mode: mode,
            signatureFormat: signatureFormat,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        // sign package manifest(s)
        let manifests = try Self.findManifests(packageDirectory: packageDirectory)
        try manifests.forEach {
            observabilityScope.emit(info: "signing \($0)")
            let signedManifestPath = workingDirectory.appending($0)

            var manifest = try fileSystem.readFileContents(packageDirectory.appending($0)).contents
            let signature = try SignatureProvider.sign(
                content: manifest,
                identity: signingIdentity,
                intermediateCertificates: intermediateCertificates,
                format: signatureFormat,
                observabilityScope: observabilityScope
            )
            manifest
                .append(
                    contentsOf: Array(
                        "\n// signature: \(signatureFormat.rawValue);\(Data(signature).base64EncodedString())"
                            .utf8
                    )
                )

            try fileSystem.writeFileContents(signedManifestPath) { stream in
                stream.write(manifest)
            }
        }

        // create the archive
        observabilityScope.emit(info: "archiving the source at '\(packageDirectory)'")
        let archivePath = try PackageArchiver.archive(
            packageIdentity: packageIdentity,
            packageVersion: packageVersion,
            packageDirectory: packageDirectory,
            workingDirectory: workingDirectory,
            workingFilesToCopy: manifests,
            cancellator: cancellator,
            observabilityScope: observabilityScope
        )
        let archive = try localFileSystem.readFileContents(archivePath).contents

        // sign the archive
        observabilityScope.emit(info: "signing the archive at '\(archivePath)'")
        let archiveSignature = try SignatureProvider.sign(
            content: archive,
            identity: signingIdentity,
            intermediateCertificates: intermediateCertificates,
            format: signatureFormat,
            observabilityScope: observabilityScope
        )
        let archiveSignaturePath = workingDirectory.appending("\(packageIdentity)-\(packageVersion).sig")
        try fileSystem.writeFileContents(archiveSignaturePath) { stream in
            stream.write(archiveSignature)
        }

        var signedMetadata: SignedItem? = .none
        if let metadataPath {
            observabilityScope.emit(info: "signing metadata at '\(metadataPath)'")
            let metadata = try localFileSystem.readFileContents(metadataPath).contents
            let metadataSignature = try SignatureProvider.sign(
                content: metadata,
                identity: signingIdentity,
                intermediateCertificates: intermediateCertificates,
                format: signatureFormat,
                observabilityScope: observabilityScope
            )
            let metadataSignaturePath = workingDirectory.appending("\(packageIdentity)-\(packageVersion)-metadata.sig")
            try fileSystem.writeFileContents(metadataSignaturePath) { stream in
                stream.write(metadataSignature)
            }
            signedMetadata = .init(path: metadataPath, signature: metadataSignature)
        }

        return ArchiveAndSignResult(
            archive: .init(path: archivePath, signature: archiveSignature),
            signedManifests: manifests,
            metadata: signedMetadata
        )
    }

    private static func signingIdentityAndIntermediateCertificates(
        mode: SigningMode,
        signatureFormat: SignatureFormat,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> (SigningIdentity, [[UInt8]]) {
        let signingIdentity: SigningIdentity
        let intermediateCertificates: [[UInt8]]
        switch mode {
        case .identityStore(let label, let intermediateCertPaths):
            let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
            let matches = signingIdentityStore.find(by: label)
            guard let identity = matches.first else {
                throw StringError("'\(label)' not found in the system identity store.")
            }
            // TODO: let user choose if there is more than one match?
            signingIdentity = identity
            intermediateCertificates = try intermediateCertPaths.map { try fileSystem.readFileContents($0).contents }
        case .certificate(let certPath, let intermediateCertPaths, let privateKeyPath):
            let certificate = try fileSystem.readFileContents(certPath).contents
            let privateKey = try fileSystem.readFileContents(privateKeyPath).contents
            signingIdentity = try SwiftSigningIdentity(
                derEncodedCertificate: certificate,
                derEncodedPrivateKey: privateKey,
                privateKeyType: signatureFormat.signingKeyType
            )
            intermediateCertificates = try intermediateCertPaths.map { try fileSystem.readFileContents($0).contents }
        }
        return (signingIdentity, intermediateCertificates)
    }

    private static func findManifests(packageDirectory: AbsolutePath) throws -> [String] {
        let packageContents = try localFileSystem.getDirectoryContents(packageDirectory)

        var manifests: [String] = []

        let manifestName = "Package.swift"
        let manifestPath = packageDirectory.appending(manifestName)
        guard localFileSystem.exists(manifestPath) else {
            throw StringError("No \(manifestName) found at \(packageDirectory).")
        }
        manifests.append(manifestName)

        let regex = try RegEx(pattern: #"^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$"#)
        let versionSpecificManifests: [String] = packageContents.filter { file in
            let matchGroups = regex.matchGroups(in: file)
            return !matchGroups.isEmpty
        }
        manifests.append(contentsOf: versionSpecificManifests)

        return manifests
    }

    static func computeSigningMode(
        signingIdentity: String?,
        privateKeyPath: AbsolutePath?,
        certificateChainPaths: [AbsolutePath]
    ) throws -> SigningMode {
        let signingMode: PackageArchiveSigner.SigningMode
        switch (signingIdentity, certificateChainPaths, privateKeyPath) {
        case (.none, let certChainPaths, .none) where !certChainPaths.isEmpty:
            throw StringError(
                "Both 'private-key-path' and 'cert-chain-paths' are required when one of them is set."
            )
        case (.none, let certChainPaths, .some) where certChainPaths.isEmpty:
            throw StringError(
                "Both 'private-key-path' and 'cert-chain-paths' are required when one of them is set."
            )
        case (.none, let certChainPaths, .some(let privateKeyPath)) where !certChainPaths.isEmpty:
            let certificate = certChainPaths[0]
            let intermediateCertificates = certChainPaths.count > 1 ? Array(certChainPaths[1...]) : []
            signingMode = .certificate(
                certificate: certificate,
                intermediateCertificates: intermediateCertificates,
                privateKey: privateKeyPath
            )
        case (.some(let signingStoreLabel), let certChainPaths, .none) where certChainPaths.isEmpty:
            signingMode = .identityStore(label: signingStoreLabel, intermediateCertificates: certChainPaths)
        default:
            throw StringError(
                "Either 'signing-identity' or 'private-key-path' (together with 'cert-chain-paths') must be provided."
            )
        }
        return signingMode
    }

    struct ArchiveAndSignResult {
        let archive: SignedItem
        let signedManifests: [String]
        let metadata: SignedItem?
    }

    struct SignedItem {
        let path: AbsolutePath
        let signature: [UInt8]
    }

    /*
        @discardableResult
        static func sign(
            archivePath: AbsolutePath,
            signaturePath: AbsolutePath,
            mode: SigningMode,
            signatureFormat: SignatureFormat,
            fileSystem: FileSystem,
            observabilityScope: ObservabilityScope
        ) throws -> [UInt8] {
            let signatures = try Self.sign(
                contentPaths: [archivePath],
                contentSignaturePaths: [archivePath: signaturePath],
                mode: mode,
                signatureFormat: signatureFormat,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )

            guard let signature = signatures[archivePath] else {
                throw StringError("signing archive at \(archivePath) failed")
            }
            return signature
        }

        @discardableResult
        static func sign(
            contentPaths: [AbsolutePath],
            contentSignaturePaths: [AbsolutePath: AbsolutePath],
            mode: SigningMode,
            signatureFormat: SignatureFormat,
            fileSystem: FileSystem,
            observabilityScope: ObservabilityScope
        ) throws -> [AbsolutePath: [UInt8]] {
            let contentBytes = Dictionary(uniqueKeysWithValues: try contentPaths.map {
                let contentBytes = try fileSystem.readFileContents($0).contents
                guard !contentBytes.isEmpty else {
                    throw StringError("the file at \($0) is empty")
                }
                return ($0, contentBytes)
            })

            let signingIdentity: SigningIdentity
            let intermediateCertificates: [[UInt8]]
            switch mode {
            case .identityStore(let label, let intermediateCertPaths):
                let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
                let matches = signingIdentityStore.find(by: label)
                guard let identity = matches.first else {
                    throw StringError("'\(label)' not found in the system identity store.")
                }
                // TODO: let user choose if there is more than one match?
                signingIdentity = identity
                intermediateCertificates = try intermediateCertPaths.map { try fileSystem.readFileContents($0).contents }
            case .certificate(let certPath, let intermediateCertPaths, let privateKeyPath):
                let certificate = try fileSystem.readFileContents(certPath).contents
                let privateKey = try fileSystem.readFileContents(privateKeyPath).contents
                signingIdentity = try SwiftSigningIdentity(
                    derEncodedCertificate: certificate,
                    derEncodedPrivateKey: privateKey,
                    privateKeyType: signatureFormat.signingKeyType
                )
                intermediateCertificates = try intermediateCertPaths.map { try fileSystem.readFileContents($0).contents }
            }

            let contentSignatures = try Dictionary(uniqueKeysWithValues: contentBytes.map { contentPath, content in
                let signature = try SignatureProvider.sign(
                    content: content,
                    identity: signingIdentity,
                    intermediateCertificates: intermediateCertificates,
                    format: signatureFormat,
                    observabilityScope: observabilityScope
                )
                return (contentPath, signature)
            })

            try contentSignaturePaths.forEach { contentPath, signaturePath in
                if let signature = contentSignatures[contentPath] {
                    try fileSystem.writeFileContents(signaturePath) { stream in
                        stream.write(signature)
                    }
                }
            }

            return contentSignatures
        }
     */

    enum SigningMode {
        case identityStore(label: String, intermediateCertificates: [AbsolutePath])
        case certificate(certificate: AbsolutePath, intermediateCertificates: [AbsolutePath], privateKey: AbsolutePath)
    }
}

enum PackageArchiver {
    static func archive(
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        workingFilesToCopy: [String],
        cancellator: Cancellator?,
        observabilityScope: ObservabilityScope
    ) throws -> AbsolutePath {
        let archivePath = workingDirectory.appending("\(packageIdentity)-\(packageVersion).zip")

        // create temp location for sources
        let sourceDirectory = workingDirectory.appending(components: "source", "\(packageIdentity)")
        try localFileSystem.createDirectory(sourceDirectory, recursive: true)

        // TODO: filter other unnecessary files, and/or .swiftpmignore file
        let ignoredContent = [".build", ".git", ".gitignore", ".swiftpm"]
        let packageContent = try localFileSystem.getDirectoryContents(packageDirectory)
        for item in (packageContent.filter { !ignoredContent.contains($0) }) {
            try localFileSystem.copy(
                from: packageDirectory.appending(component: item),
                to: sourceDirectory.appending(component: item)
            )
        }

        for item in workingFilesToCopy {
            let replacementPath = workingDirectory.appending(item)
            let replacement = try localFileSystem.readFileContents(replacementPath)

            let toBeReplacedPath = sourceDirectory.appending(item)

            observabilityScope.emit(info: "replacing '\(toBeReplacedPath)' with '\(replacementPath)'")
            try localFileSystem.writeFileContents(toBeReplacedPath, bytes: replacement)
        }

        try SwiftPackageTool.archiveSource(
            at: sourceDirectory,
            to: archivePath,
            fileSystem: localFileSystem,
            cancellator: cancellator
        )

        return archivePath
    }
}
