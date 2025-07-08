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
    struct Discover: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get a package registry entry."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: .init("URL pointing towards package identifiers", valueName: "scm-url"))
        var url: SourceControlURL

        @Flag(name: .customLong("allow-insecure-http"), help: "Allow using a non-HTTPS registry URL.")
        var allowInsecureHTTP: Bool = false

        @Option(name: [.customLong("url"), .customLong("registry-url")], help: "Override registry URL.")
        var registryURL: URL?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let packageDirectory = try resolvePackageDirectory(swiftCommandState)
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

            let set = try await registryClient.lookupIdentities(scmURL: url, observabilityScope: swiftCommandState.observabilityScope)

            if set.isEmpty {
                throw ValidationError.invalidLookupURL(url)
            }

            print(set)
        }

        private func resolvePackageDirectory(_ swiftCommandState: SwiftCommandState) throws -> AbsolutePath {
            let directory = try self.globalOptions.locations.packageDirectory
                ?? swiftCommandState.getPackageRoot()

            guard localFileSystem.isDirectory(directory) else {
                throw StringError("No package found at '\(directory)'.")
            }

            return directory
        }

        private func resolveAuthorizationProvider(_ swiftCommandState: SwiftCommandState) throws -> AuthorizationProvider {
            guard let provider = try swiftCommandState.getRegistryAuthorizationProvider() else {
                throw ValidationError.unknownCredentialStore
            }

            return provider
        }
    }
}


extension SourceControlURL: ExpressibleByArgument {}
