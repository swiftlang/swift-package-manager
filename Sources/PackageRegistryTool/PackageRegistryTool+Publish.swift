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

        @Option(name: [.customLong("id"), .customLong("package-id")] , help: "The package identity")
        var packageIdentity: PackageIdentity

        @Option(name: [.customLong("version"), .customLong("package-version")], help: "The package version")
        var packageVersion: Version

        @Option(name: [.customLong("url"), .customLong("registry-url")], help: "The registry URL")
        var registryURL: URL?

        @Option(
            name: .customLong("output-directory"),
            help: "The path of the directory where output file(s) will be written"
        )
        var customWorkingDirectory: AbsolutePath?

        @Option(
            name: .customLong("metadata-path"),
            help: "The path to the package metadata JSON file"
        )
        var customMetadataPath: AbsolutePath?

        @Option(help: .hidden) // help: "Signature format identifier. Defaults to 'cms-1.0.0'.
        var signatureFormat: SignatureFormat = .CMS_1_0_0

        @Option(help: "The label of the signing identity to be retrieved from the system's secrets store if supported")
        var signingIdentity: String?

        @Option(help: "The path to the certificate's PKCS#8 private key (DER-encoded)")
        var privateKeyPath: AbsolutePath?

        @Option(
            help: "Paths to all of the certificates (DER-encoded) in the chain. The certificate used for signing must be listed first and the root certificate last."
        )
        var certificateChainPaths: [AbsolutePath] = []

        func run(_ swiftTool: SwiftTool) throws {
            let configuration = try getRegistriesConfig(swiftTool).configuration

            // validate package location
            let packageDirectory = try self.globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
            guard localFileSystem.isDirectory(packageDirectory) else {
                throw StringError("No package found at '\(packageDirectory)'.")
            }

            // validate package identity
            guard let packageScopeAndName = self.packageIdentity.scopeAndName else {
                throw ValidationError.invalidPackageIdentity(self.packageIdentity)
            }

            // compute and validate registry URL
            let registryURL: URL? = self.registryURL ?? {
                if let registry = configuration.registry(for: packageScopeAndName.scope) {
                    return registry.url
                }
                if let registry = configuration.defaultRegistry {
                    return registry.url
                }
                return .none
            }()

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
                authorizationProvider: authorizationProvider
            )

            // step 1: publishing configuration
            let metadataPath = self.customMetadataPath ?? packageDirectory.appending(component: Self.metadataFilename)
            guard localFileSystem.exists(metadataPath) else {
                throw StringError(
                    "Publishing to '\(registryURL)' requires metadata file but none was found at '\(metadataPath)'."
                )
            }

            let publishConfiguration = RegistryClient.PublishConfiguration(
                signing: .init(
                    required: self.signingIdentity != nil || self.privateKeyPath != nil,
                    acceptedSignatureFormats: [.CMS_1_0_0],
                    trustedRootCertificates: []
                )
            )

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
            var signature: Data? = .none
            if publishConfiguration.signing.required {
                swiftTool.observabilityScope.emit(info: "signing the archive at '\(archivePath)'")
                signature = try self.sign(
                    archivePath: archivePath,
                    signatureFormat: self.signatureFormat,
                    signingIdentity: self.signingIdentity,
                    privateKeyPath: self.privateKeyPath,
                    observabilityScope: swiftTool.observabilityScope
                )
            }

            // step 4: publish the package
            swiftTool.observabilityScope
                .emit(info: "publishing '\(self.packageIdentity)' archive at '\(archivePath)' to '\(registryURL)'")
            // TODO: handle signature
            let result = try tsc_await { callback in
                registryClient.publish(
                    registryURL: registryURL,
                    packageIdentity: self.packageIdentity,
                    packageVersion: self.packageVersion,
                    packageArchive: archivePath,
                    packageMetadata: self.customMetadataPath,
                    signature: signature,
                    fileSystem: localFileSystem,
                    observabilityScope: swiftTool.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: callback
                )
            }

            switch result {
            case .published(.none):
                print("\(packageIdentity)@\(packageVersion) was successfully published to \(registryURL)")
            case .published(.some(let location)):
                print("\(packageIdentity)@\(packageVersion) was successfully published to \(registryURL) and is available at \(location)")
            case .processing(let statusURL, _):
                print("\(packageIdentity)@\(packageVersion) was successfully submitted to \(registryURL) and is being processed. Publishing status is available at \(statusURL)")
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
            let archivePath = workingDirectory.appending(component: "\(packageIdentity)-\(packageVersion).zip")

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

        func sign(
            archivePath: AbsolutePath,
            signatureFormat: SignatureFormat,
            signingIdentity: String?,
            privateKeyPath: AbsolutePath?,
            observabilityScope: ObservabilityScope
        ) throws -> Data {
            fatalError("not implemented")
        }
    }
}

enum SignatureFormat: ExpressibleByArgument {
    case CMS_1_0_0

    init?(argument: String) {
        switch argument.lowercased() {
        case "cms-1.0.0":
            self = .CMS_1_0_0
        default:
            return nil
        }
    }
}
