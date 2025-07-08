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
import PackageFingerprint
import PackageRegistry
import PackageSigning
import Workspace

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import X509 // FIXME: need this import or else SwiftSigningIdentity initializer fails
#else
import X509
#endif

import struct TSCBasic.ByteString
import struct TSCBasic.RegEx
import struct TSCBasic.SHA256

import struct TSCUtility.Version

extension PackageRegistryCommand {
    struct Get: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get a package registry entry."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: .init("The package identifier.", valueName: "package-id"))
        var packageIdentity: PackageIdentity

        @Option(help: .init("The package release version being queried.", valueName: "package-version"))
        var packageVersion: Version?

        @Flag(help: .init("Fetch the Package.swift manifest of the registry entry", valueName: "manifest"))
        var manifest: Bool = false

        @Option(help: .init("Swift tools version of the manifest", valueName: "custom-tools-version"))
        var customToolsVersion: String?

        @Flag(name: .customLong("allow-insecure-http"), help: "Allow using a non-HTTPS registry URL.")
        var allowInsecureHTTP: Bool = false

        @Option(name: [.customLong("url"), .customLong("registry-url")], help: "Override registry URL.")
        var registryURL: URL?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let packageDirectory = try resolvePackageDirectory(swiftCommandState)
            let registryURL = try resolveRegistryURL(swiftCommandState)
            let authorizationProvider = try resolveAuthorizationProvider(swiftCommandState)

            let registryClient = RegistryClient(
                configuration: try getRegistriesConfig(swiftCommandState, global: false).configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                skipSignatureValidation: false,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: authorizationProvider,
                delegate: .none,
                checksumAlgorithm: SHA256()
            )

            try await fetchRegistryData(using: registryClient, swiftCommandState: swiftCommandState)
        }

        private func resolvePackageDirectory(_ swiftCommandState: SwiftCommandState) throws -> AbsolutePath {
            let directory = try self.globalOptions.locations.packageDirectory
                ?? swiftCommandState.getPackageRoot()

            guard localFileSystem.isDirectory(directory) else {
                throw StringError("No package found at '\(directory)'.")
            }

            return directory
        }

        private func resolveRegistryURL(_ swiftCommandState: SwiftCommandState) throws -> URL {
            let config = try getRegistriesConfig(swiftCommandState, global: false).configuration
            guard let identity = self.packageIdentity.registry else {
                throw ValidationError.invalidPackageIdentity(self.packageIdentity)
            }

            guard let url = self.registryURL ?? config.registry(for: identity.scope)?.url else {
                throw ValidationError.unknownRegistry
            }

            let allowHTTP = try self.allowInsecureHTTP && (config.authentication(for: url) == nil)
            try url.validateRegistryURL(allowHTTP: allowHTTP)

            return url
        }

        private func resolveAuthorizationProvider(_ swiftCommandState: SwiftCommandState) throws -> AuthorizationProvider {
            guard let provider = try swiftCommandState.getRegistryAuthorizationProvider() else {
                throw ValidationError.unknownCredentialStore
            }

            return provider
        }

        private func fetchToolsVersion() -> ToolsVersion? {
            return customToolsVersion.flatMap { ToolsVersion(string: $0) }
        }

        private func fetchRegistryData(
            using client: RegistryClient,
            swiftCommandState: SwiftCommandState
        ) async throws {
            let scope = swiftCommandState.observabilityScope

            if manifest {
                guard let version = packageVersion else {
                    throw ValidationError.noPackageVersion(packageIdentity)
                }

                let toolsVersion = fetchToolsVersion()
                let content = try await client.getManifestContent(
                    package: self.packageIdentity,
                    version: version,
                    customToolsVersion: toolsVersion,
                    observabilityScope: scope
                )

                print(content)
                return
            }

            if let version = packageVersion {
                let metadata = try await client.getPackageVersionMetadata(
                    package: self.packageIdentity,
                    version: version,
                    fileSystem: localFileSystem,
                    observabilityScope: scope
                )

                print(metadata)
            } else {
                let metadata = try await client.getPackageMetadata(
                    package: self.packageIdentity,
                    observabilityScope: scope
                )

                print(metadata)
            }
        }
    }
}
