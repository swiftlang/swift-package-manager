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
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    struct Publish: AsyncSwiftCommand {
        static let metadataFilename = "package-metadata.json"

        static let configuration = CommandConfiguration(
            abstract: "Publish to a registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(name: [.customLong("id"), .customLong("package-id")], help: "The package identifier.")
        var packageIdentity: PackageIdentity

        @Option(
            name: [.customLong("version"), .customLong("package-version")],
            help: "The package release version being created."
        )
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

        @Option(help: "The path to the signing certificate (DER-encoded).")
        var certificatePath: AbsolutePath?

        @Option(help: "Dry run only; prepare the archive and sign it but do not publish to the registry.")
        var dryRun: Bool = false

        func run(_ swiftTool: SwiftTool) async throws {
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
                authorizationProvider: authorizationProvider
            )

            // step 1: publishing configuration
            let publishConfiguration = PublishConfiguration(
                metadataLocation: self.customMetadataPath
                    .flatMap { .external($0) } ??
                    .sourceTree(packageDirectory.appending(component: Self.metadataFilename)),
                signing: .init(
                    required: self.signingIdentity != nil || self.privateKeyPath != nil,
                    format: self.signatureFormat,
                    signingIdentity: self.signingIdentity,
                    privateKeyPath: self.privateKeyPath,
                    certificatePath: self.certificatePath
                )
            )

            guard localFileSystem.exists(publishConfiguration.metadataLocation.path) else {
                throw StringError(
                    "Publishing to '\(registryURL)' requires metadata file but none was found at '\(publishConfiguration.metadataLocation)'."
                )
            }

            if publishConfiguration.signing.privateKeyPath != nil {
                guard publishConfiguration.signing.certificatePath != nil else {
                    throw StringError(
                        "Both 'privateKeyPath' and 'certificatePath' are required when one of them is set."
                    )
                }
            } else {
                guard publishConfiguration.signing.certificatePath == nil else {
                    throw StringError(
                        "Both 'privateKeyPath' and 'certificatePath' are required when one of them is set."
                    )
                }
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
            var signature: Data? = .none
            if publishConfiguration.signing.required {
                swiftTool.observabilityScope.emit(info: "signing the archive at '\(archivePath)'")
                signature = try await self.sign(
                    packageIdentity: self.packageIdentity,
                    packageVersion: self.packageVersion,
                    archivePath: archivePath,
                    configuration: publishConfiguration.signing,
                    workingDirectory: workingDirectory,
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
                .emit(info: "publishing '\(self.packageIdentity)' archive at '\(archivePath)' to '\(registryURL)'")
            // TODO: handle signature
            let result = try await registryClient.publish(
                registryURL: registryURL,
                packageIdentity: self.packageIdentity,
                packageVersion: self.packageVersion,
                packageArchive: archivePath,
                packageMetadata: self.customMetadataPath,
                signature: signature,
                fileSystem: localFileSystem,
                observabilityScope: swiftTool.observabilityScope
            )

            switch result {
            case .published(.none):
                print("\(packageIdentity)@\(packageVersion) was successfully published to \(registryURL)")
            case .published(.some(let location)):
                print(
                    "\(packageIdentity)@\(packageVersion) was successfully published to \(registryURL) and is available at \(location)"
                )
            case .processing(let statusURL, _):
                print(
                    "\(packageIdentity)@\(packageVersion) was successfully submitted to \(registryURL) and is being processed. Publishing status is available at \(statusURL)."
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
            packageIdentity: PackageIdentity,
            packageVersion: Version,
            archivePath: AbsolutePath,
            configuration: PublishConfiguration.Signing,
            workingDirectory: AbsolutePath,
            observabilityScope: ObservabilityScope
        ) async throws -> Data {
            let archiveData = try Data(localFileSystem.readFileContents(archivePath).contents)

            var signingIdentity: SigningIdentity?
            if let signingIdentityLabel = configuration.signingIdentity {
                let signingIdentityStore = SigningIdentityStore(observabilityScope: observabilityScope)
                let matches = try await signingIdentityStore.find(by: signingIdentityLabel)
                guard !matches.isEmpty else {
                    throw StringError("'\(signingIdentityLabel)' not found in the system identity store.")
                }
                // TODO: let user choose if there is more than one match?
                signingIdentity = matches.first
            } else if let privateKeyPath = configuration.privateKeyPath,
                      let certificatePath = configuration.certificatePath
            {
                let certificateData = try Data(localFileSystem.readFileContents(certificatePath).contents)
                let privateKeyData = try Data(localFileSystem.readFileContents(privateKeyPath).contents)
                signingIdentity = SwiftSigningIdentity(
                    certificate: Certificate(derEncoded: certificateData),
                    privateKey: try configuration.format.privateKey(derRepresentation: privateKeyData)
                )
            }

            guard let signingIdentity = signingIdentity else {
                throw StringError("Cannot sign archive without signing identity.")
            }

            let signature = try await SignatureProvider.sign(
                archiveData,
                with: signingIdentity,
                in: configuration.format,
                observabilityScope: observabilityScope
            )

            let signaturePath = workingDirectory.appending(component: "\(packageIdentity)-\(packageVersion).sig")
            try localFileSystem.writeFileContents(signaturePath) { stream in
                stream.write(signature)
            }

            return signature
        }
    }
}

struct PublishConfiguration {
    let metadataLocation: MetadataLocation
    let signing: Signing

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

    struct Signing {
        let required: Bool
        let format: SignatureFormat
        var signingIdentity: String?
        var privateKeyPath: AbsolutePath?
        var certificatePath: AbsolutePath?
    }
}

extension SignatureFormat: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

// TODO: migrate registry client to async
extension RegistryClient {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    public func publish(
        registryURL: URL,
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageArchive: AbsolutePath,
        packageMetadata: AbsolutePath?,
        signature: Data?,
        timeout: DispatchTimeInterval? = .none,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> PublishResult {
        try await withCheckedThrowingContinuation { continuation in
            self.publish(
                registryURL: registryURL,
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                packageArchive: packageArchive,
                packageMetadata: packageMetadata,
                signature: signature,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                callbackQueue: .sharedConcurrent,
                completion: continuation.resume(with:)
            )
        }
    }
}
