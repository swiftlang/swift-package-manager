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

extension SwiftPackageRegistryTool {
    struct Publish: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Publish to a registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(name: .customLong("id"), help: "The package identity")
        var packageIdentity: PackageIdentity

        @Option(help: "The package version")
        var version: Version

        @Option(name: .customLong("url"), help: "The registry URL")
        var registryURL: URL?

        @Option(help: "The path of the directory where output file(s) will be written")
        var outputDirectory: AbsolutePath?

        @Option(help: "The path to the package metadata JSON file")
        var metadataPath: AbsolutePath?

        @Option(help: "Signature format identifier. Defaults to 'cms-1.0.0'.")
        var signatureFormat: SignatureFormat = .CMS_1_0_0

        @Option(help: "The label of the signing identity to be retrieved from the system's secrets store if supported")
        var signingIdentity: String?

        @Option(help: "The path to the certificate's PKCS#8 private key (DER-encoded)")
        var privateKeyPath: AbsolutePath?

        @Option(
            help: "Paths to all of the certificates (DER-encoded) in the chain. The certificate used for signing must be listed first and the root certificate last."
        )
        var certificateChainPaths: [AbsolutePath]

        func run(_ swiftTool: SwiftTool) throws {
            let configuration = try getRegistriesConfig(swiftTool).configuration

            // validate identity
            guard let packageScopeAndName = self.packageIdentity.scopeAndName else {
                throw ConfigurationError.invalidPackageIdentity(self.packageIdentity)
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
                throw ConfigurationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

            // step 1: get registry publish requirements

            guard let authorizationProvider = try swiftTool.getRegistryAuthorizationProvider() else {
                throw StringError("No credential store available")
            }

            let registryClient = RegistryClient(
                configuration: configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                authorizationProvider: authorizationProvider
            )

            let publishRequirements = try tsc_await { callback in
                registryClient.getPublishRequirements(
                    registryURL: registryURL,
                    observabilityScope: swiftTool.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: callback
                )
            }
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
