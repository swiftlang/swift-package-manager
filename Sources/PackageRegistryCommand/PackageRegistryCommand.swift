//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
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
import Workspace

public struct PackageRegistryCommand: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package-registry",
        _superCommandName: "swift",
        abstract: "Interact with package registry and manage related configuration",
        discussion: "SEE ALSO: swift package",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            Set.self,
            Unset.self,
            Login.self,
            Logout.self,
            Publish.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}

    struct Set: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a custom registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        @Flag(name: .customLong("allow-insecure-http"), help: "Allow using a non-HTTPS registry URL")
        var allowInsecureHTTP: Bool = false

        @Argument(help: "The registry URL")
        var url: URL

        var registryURL: URL {
            self.url
        }

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try self.registryURL.validateRegistryURL(allowHTTP: self.allowInsecureHTTP)

            let scope = try scope.map(PackageIdentity.Scope.init(validating:))

            let set: (inout RegistryConfiguration) throws -> Void = { configuration in
                let registry = Registry(url: self.registryURL, supportsAvailability: false)
                if let scope {
                    configuration.scopedRegistries[scope] = registry
                } else {
                    configuration.defaultRegistry = registry
                }
            }

            let configuration = try getRegistriesConfig(swiftCommandState, global: self.global)
            if self.global {
                try configuration.updateShared(with: set)
            } else {
                try configuration.updateLocal(with: set)
            }
        }
    }

    struct Unset: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a configured registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let scope = try scope.map(PackageIdentity.Scope.init(validating:))

            let unset: (inout RegistryConfiguration) throws -> Void = { configuration in
                if let scope {
                    guard let _ = configuration.scopedRegistries[scope] else {
                        throw ConfigurationError.missingScope(scope)
                    }
                    configuration.scopedRegistries.removeValue(forKey: scope)
                } else {
                    guard let _ = configuration.defaultRegistry else {
                        throw ConfigurationError.missingScope()
                    }
                    configuration.defaultRegistry = nil
                }
            }

            let configuration = try getRegistriesConfig(swiftCommandState, global: self.global)
            if self.global {
                try configuration.updateShared(with: unset)
            } else {
                try configuration.updateLocal(with: unset)
            }
        }
    }

    // common utility

    enum ConfigurationError: Swift.Error {
        case missingScope(PackageIdentity.Scope? = nil)
    }

    enum ValidationError: Swift.Error {
        case invalidURL(URL)
        case invalidPackageIdentity(PackageIdentity)
        case unknownRegistry
        case unknownCredentialStore
        case invalidCredentialStore(Error)
        case credentialLengthLimitExceeded(Int)
    }

    static func getRegistriesConfig(_ swiftCommandState: SwiftCommandState, global: Bool) throws -> Workspace.Configuration.Registries {
        if global {
            let sharedRegistriesFile = Workspace.DefaultLocations.registriesConfigurationFile(
                at: swiftCommandState.sharedConfigurationDirectory
            )
            // Workspace not needed when working with user-level registries config
            return try .init(
                fileSystem: swiftCommandState.fileSystem,
                localRegistriesFile: .none,
                sharedRegistriesFile: sharedRegistriesFile
            )
        } else {
            let workspace = try swiftCommandState.getActiveWorkspace()
            return try .init(
                fileSystem: swiftCommandState.fileSystem,
                localRegistriesFile: workspace.location.localRegistriesConfigurationFile,
                sharedRegistriesFile: workspace.location.sharedRegistriesConfigurationFile
            )
        }
    }
}

extension URL {
    func validateRegistryURL(allowHTTP: Bool = false) throws {
        guard self.scheme == "https" || (self.scheme == "http" && allowHTTP) else {
            throw PackageRegistryCommand.ValidationError.invalidURL(self)
        }
    }
}

extension PackageRegistryCommand.ConfigurationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .missingScope(let scope?):
            return "No existing entry for scope: \(scope)"
        case .missingScope:
            return "No existing entry for default scope"
        }
    }
}

extension PackageRegistryCommand.ValidationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidURL(let url):
            return "invalid URL: \(url)"
        case .invalidPackageIdentity(let identity):
            return "invalid package identifier '\(identity)'"
        case .unknownRegistry:
            return "unknown registry, is one configured?"
        case .unknownCredentialStore:
            return "no credential store available"
        case .invalidCredentialStore(let error):
            return "credential store is invalid: \(error.interpolationDescription)"
        case .credentialLengthLimitExceeded(let limit):
            return "password or access token must be \(limit) characters or less"
        }
    }
}
