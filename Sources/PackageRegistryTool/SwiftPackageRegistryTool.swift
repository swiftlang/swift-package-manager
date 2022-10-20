//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
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
import TSCBasic
import SPMBuildCore
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import Workspace
import Foundation
import PackageRegistry

private enum RegistryConfigurationError: Swift.Error {
    case missingScope(PackageIdentity.Scope? = nil)
    case invalidURL(String)
}

extension RegistryConfigurationError: CustomStringConvertible {
    var description: String {
        switch self {
        case .missingScope(let scope?):
            return "no existing entry for scope: \(scope)"
        case .missingScope:
            return "no existing entry for default scope"
        case .invalidURL(let url):
            return "invalid URL: \(url)"
        }
    }
}

public struct SwiftPackageRegistryTool: ParsableCommand {
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
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}

    struct Set: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a custom registry")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        @Argument(help: "The registry URL")
        var url: String

        func run(_ swiftTool: SwiftTool) throws {
            guard let url = URL(string: self.url), url.scheme == "https" else {
                throw RegistryConfigurationError.invalidURL(self.url)
            }

            let scope = try scope.map(PackageIdentity.Scope.init(validating:))

            let set: (inout RegistryConfiguration) throws -> Void = { configuration in
                if let scope = scope {
                    configuration.scopedRegistries[scope] = .init(url: url)
                } else {
                    configuration.defaultRegistry = .init(url: url)
                }
            }

            let configuration = try getRegistriesConfig(swiftTool)
            if self.global {
                try configuration.updateShared(with: set)
            } else {
                try configuration.updateLocal(with: set)
            }
        }
    }

    struct Unset: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a configured registry")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        func run(_ swiftTool: SwiftTool) throws {
            let scope = try scope.map(PackageIdentity.Scope.init(validating:))

            let unset: (inout RegistryConfiguration) throws -> Void = { configuration in
                if let scope = scope {
                    guard let _ = configuration.scopedRegistries[scope] else {
                        throw RegistryConfigurationError.missingScope(scope)
                    }
                    configuration.scopedRegistries.removeValue(forKey: scope)
                } else {
                    guard let _ = configuration.defaultRegistry else {
                        throw RegistryConfigurationError.missingScope()
                    }
                    configuration.defaultRegistry = nil
                }
            }

            let configuration = try getRegistriesConfig(swiftTool)
            if self.global {
                try configuration.updateShared(with: unset)
            } else {
                try configuration.updateLocal(with: unset)
            }
        }
    }
    
    struct Login: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Log in to a registry")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Argument(help: "The registry URL")
        var url: String
        
        @Option(help: "Username")
        var username: String?

        @Option(help: "Password")
        var password: String?
        
        @Option(help: "Access token")
        var token: String?
        
        @Flag(help: "Allow writing to .netrc file without confirmation")
        var noConfirm: Bool = false
        
        private static let PLACEHOLDER_TOKEN_USER = "token"

        func run(_ swiftTool: SwiftTool) throws {
            guard let url = URL(string: self.url), url.scheme == "https", let host = url.host else {
                throw RegistryConfigurationError.invalidURL(self.url)
            }
            
            // We need to be able to read/write credentials
            guard let authorizationProvider = try swiftTool.getAuthorizationProvider() else {
                throw StringError("No credential storage available")
            }

            let authenticationType: RegistryConfiguration.AuthenticationType
            let storeUsername: String
            let storePassword: String
            var saveChanges = true
            
            if let username = self.username {
                authenticationType = .basic

                storeUsername = username
                if let password = self.password {
                    // User provided password
                    storePassword = password
                } else if let stored = authorizationProvider.authentication(for: url), stored.user == storeUsername {
                    // Password found in credential storage
                    storePassword = stored.password
                    saveChanges = false
                } else {
                    // Prompt user for password
                    storePassword = String(cString: getpass("Enter password for '\(storeUsername)': "))
                }
            } else {
                authenticationType = .token

                // All token auth accounts have the same placeholder value
                storeUsername = Self.PLACEHOLDER_TOKEN_USER
                if let token = self.token {
                    // User provided token
                    storePassword = token
                } else if let stored = authorizationProvider.authentication(for: url), stored.user == storeUsername {
                    // Token found in credential storage
                    storePassword = stored.password
                    saveChanges = false
                } else {
                    // Prompt user for token
                    storePassword = String(cString: getpass("Enter access token: "))
                }
            }
            
            let authorizationWriter = authorizationProvider as? AuthorizationWriter
            if saveChanges, authorizationWriter == nil {
                throw StringError("Credential storage must be writable")
            }

            // Save in cache so we can try the credentials and persist to storage only if login succeeds
            try tsc_await { callback in
                authorizationWriter?.addOrUpdate(
                    for: url,
                    user: storeUsername,
                    password: storePassword,
                    persist: false,
                    callback: callback
                )
            }
            
            // `url` can either be base URL of the registry, in which case the login API
            // is assumed to be at /login, or the full URL of the login API.
            var loginAPIPath: String?
            if !url.path.isEmpty, url.path != "/" {
                loginAPIPath = url.path
            }
            
            guard let loginURL = URL(string: "https://\(host)\(loginAPIPath ?? "/login")") else {
                throw RegistryConfigurationError.invalidURL(self.url)
            }
            
            let configuration = try getRegistriesConfig(swiftTool)
            
            // Build a RegistryConfiguration with the given authentication settings
            var registryConfiguration = configuration.configuration
            registryConfiguration.registryAuthentication[host] = .init(type: authenticationType, loginAPIPath: loginAPIPath)

            // Build a RegistryClient to test login credentials (fingerprints don't matter in this case)
            let registryClient = RegistryClient(
                configuration: registryConfiguration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                authorizationProvider: authorizationProvider
            )

            // Try logging in
            try tsc_await { callback in
                registryClient.login(
                    url: loginURL,
                    timeout: .seconds(3),
                    observabilityScope: swiftTool.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: callback
                )
            }
            print("Login successful.")
            
            // Login successful. Persist credentials to storage.
            
            let osStore = !(authorizationWriter is NetrcAuthorizationProvider)
            
            // Prompt if writing to .netrc and --no-confirm is not set
            if !osStore, !self.noConfirm {
                print("""

                WARNING: Secure credential storage is not supported on this platform.
                Your credentials will be written out to .netrc.
                """)
                print("Continue? (Y/N): ")
                guard readLine()?.lowercased() == "y" else {
                    print("Credentials not saved. Exiting...")
                    return
                }
            }
            
            if saveChanges {
                try tsc_await { callback in
                    authorizationWriter?.addOrUpdate(
                        for: url,
                        user: storeUsername,
                        password: storePassword,
                        persist: true,
                        callback: callback
                    )
                }
                
                if osStore {
                    print("\nCredentials have been saved to the operating system's secure credential store.")
                } else {
                    print("\nCredentials have been saved to .netrc.")
                }
            }
            
            // Update global registry configuration file
            let update: (inout RegistryConfiguration) throws -> Void = { configuration in
                configuration.registryAuthentication[host] = .init(type: authenticationType, loginAPIPath: loginAPIPath)
            }
            try configuration.updateShared(with: update)

            print("Registry configuration updated.")
        }
    }
    
    struct Logout: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Log out from a registry")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user")
        var global: Bool = false

        @Option(help: "Associate the registry with a given scope")
        var scope: String?

        func run(_ swiftTool: SwiftTool) throws {
            let scope = try scope.map(PackageIdentity.Scope.init(validating:))

            let unset: (inout RegistryConfiguration) throws -> Void = { configuration in
                if let scope = scope {
                    guard let _ = configuration.scopedRegistries[scope] else {
                        throw RegistryConfigurationError.missingScope(scope)
                    }
                    configuration.scopedRegistries.removeValue(forKey: scope)
                } else {
                    guard let _ = configuration.defaultRegistry else {
                        throw RegistryConfigurationError.missingScope()
                    }
                    configuration.defaultRegistry = nil
                }
            }

            let configuration = try getRegistriesConfig(swiftTool)
            if self.global {
                try configuration.updateShared(with: unset)
            } else {
                try configuration.updateLocal(with: unset)
            }
        }
    }

    static func getRegistriesConfig(_ swiftTool: SwiftTool) throws -> Workspace.Configuration.Registries {
        let workspace = try swiftTool.getActiveWorkspace()
        return try .init(
            fileSystem: swiftTool.fileSystem,
            localRegistriesFile: workspace.location.localRegistriesConfigurationFile,
            sharedRegistriesFile: workspace.location.sharedRegistriesConfigurationFile
        )
    }
}
