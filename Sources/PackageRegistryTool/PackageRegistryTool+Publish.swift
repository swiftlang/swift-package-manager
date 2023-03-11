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
import Foundation
import PackageModel
import PackageRegistry
import PackageSigning
import TSCBasic
import Workspace

import struct TSCUtility.Version

extension SwiftPackageRegistryTool {
    struct Publish: SwiftCommand {
        static let metadataFilename = "package-metadata.json"

        static let configuration = CommandConfiguration(
            abstract: "Publish to a registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: .init("The package identifier.", valueName: "package-id"))
        var packageIdentity: PackageIdentity

        @Argument(help: .init("The package release version being created.", valueName: "package-version"))
        var packageVersion: Version

        @Option(name: [.customLong("url"), .customLong("registry-url")], help: "The registry URL.")
        var registryURL: URL?

        @Option(
            name: .customLong("scratch-directory"),
            help: "The path of the directory where working file(s) will be written."
        )
        var customWorkingDirectory: AbsolutePath?

        @Option(
            name: .customLong("metadata-path"),
            help: "The path to the package metadata JSON file if it will not be part of the source archive."
        )
        var customMetadataPath: AbsolutePath?

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

        @Flag(help: "Dry run only; prepare the archive and sign it but do not publish to the registry.")
        var dryRun: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let configuration = try getRegistriesConfig(swiftTool).configuration

            // validate package location
            let packageDirectory = try self.globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
            guard localFileSystem.isDirectory(packageDirectory) else {
                throw StringError("No package found at '\(packageDirectory)'.")
            }

            // validate package identity
            guard let registryIdentity = self.packageIdentity.registry else {
                throw ValidationError.invalidPackageIdentity(self.packageIdentity)
            }

            // compute and validate registry URL
            let registryURL = self.registryURL ?? configuration.registry(for: registryIdentity.scope)?.url
            guard let registryURL = registryURL else {
                throw ValidationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

            // validate working directory path
            if let customWorkingDirectory = self.customWorkingDirectory {
                guard localFileSystem.isDirectory(customWorkingDirectory) else {
                    throw StringError("Directory not found at '\(customWorkingDirectory)'.")
                }
            }

            let workingDirectory = customWorkingDirectory ?? Workspace.DefaultLocations
                .scratchDirectory(forRootPackage: packageDirectory).appending(components: ["registry", "publish"])
            if localFileSystem.exists(workingDirectory) {
                try localFileSystem.removeFileTree(workingDirectory)
            }

            // validate custom metadata path
            if let customMetadataPath = self.customMetadataPath {
                guard localFileSystem.exists(customMetadataPath) else {
                    throw StringError("Metadata file not found at '\(customMetadataPath)'.")
                }
            }

            guard let authorizationProvider = try swiftTool.getRegistryAuthorizationProvider() else {
                throw ValidationError.unknownCredentialStore
            }

            let registryClient = RegistryClient(
                configuration: configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: authorizationProvider,
                delegate: .none
            )

            // step 1: publishing configuration
            let metadataLocation: MetadataLocation = self.customMetadataPath
                .flatMap { .external($0) } ??
                .sourceTree(packageDirectory.appending(component: Self.metadataFilename))
            let signingRequired = self.signingIdentity != nil || self.privateKeyPath != nil || !self
                .certificateChainPaths.isEmpty

            guard localFileSystem.exists(metadataLocation.path) else {
                throw StringError(
                    "Publishing to '\(registryURL)' requires metadata file but none was found at '\(metadataLocation.path)'."
                )
            }

            // step 2: generate source archive for the package release
            swiftTool.observabilityScope.emit(info: "archiving the source at '\(packageDirectory)'")
            let archivePath = try self.archiveSource(
                packageIdentity: self.packageIdentity,
                packageVersion: self.packageVersion,
                packageDirectory: packageDirectory,
                workingDirectory: workingDirectory,
                cancellator: swiftTool.cancellator,
                observabilityScope: swiftTool.observabilityScope
            )

            // step 3: sign the source archive if needed
            var signature: [UInt8]? = .none
            if signingRequired {
                // compute signing mode
                let signingMode: PackageArchiveSigner.SigningMode
                switch (
                    self.signingIdentity,
                    self.certificateChainPaths,
                    self.privateKeyPath
                ) {
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

                swiftTool.observabilityScope.emit(info: "signing the archive at '\(archivePath)'")
                let signaturePath = workingDirectory
                    .appending("\(self.packageIdentity)-\(self.packageVersion).sig")
                signature = try PackageArchiveSigner.sign(
                    archivePath: archivePath,
                    signaturePath: signaturePath,
                    mode: signingMode,
                    signatureFormat: self.signatureFormat,
                    fileSystem: localFileSystem,
                    observabilityScope: swiftTool.observabilityScope
                )
            }

            // step 4: publish the package
            guard !self.dryRun else {
                print(
                    "\(packageIdentity)@\(packageVersion) was successfully prepared for publishing but was not published due to dry run flag. Artifacts available at '\(workingDirectory)'."
                )
                return
            }

            swiftTool.observabilityScope
                .emit(info: "publishing \(self.packageIdentity) archive at '\(archivePath)' to \(registryURL)")
            let result = try tsc_await {
                registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: self.packageIdentity,
                    packageVersion: self.packageVersion,
                    packageArchive: archivePath,
                    packageMetadata: self.customMetadataPath,
                    signature: signature,
                    signatureFormat: self.signatureFormat,
                    fileSystem: localFileSystem,
                    observabilityScope: swiftTool.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: $0
                )
            }

            switch result {
            case .published(.none):
                print("\(packageIdentity) version \(packageVersion) was successfully published to \(registryURL)")
            case .published(.some(let location)):
                print(
                    "\(packageIdentity) version \(packageVersion) was successfully published to \(registryURL) and is available at '\(location)'"
                )
            case .processing(let statusURL, _):
                print(
                    "\(packageIdentity) version \(packageVersion) was successfully submitted to \(registryURL) and is being processed. Publishing status is available at '\(statusURL)'."
                )
            }
        }

        func archiveSource(
            packageIdentity: PackageIdentity,
            packageVersion: Version,
            packageDirectory: AbsolutePath,
            workingDirectory: AbsolutePath,
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

            try SwiftPackageTool.archiveSource(
                at: sourceDirectory,
                to: archivePath,
                fileSystem: localFileSystem,
                cancellator: cancellator
            )

            return archivePath
        }
    }
}

enum MetadataLocation {
    case sourceTree(AbsolutePath)
    case external(AbsolutePath)

    var path: AbsolutePath {
        switch self {
        case .sourceTree(let path):
            return path
        case .external(let path):
            return path
        }
    }
}
