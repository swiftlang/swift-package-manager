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

#if os(Windows)
import WinSDK

private func getpass(_ prompt: String) -> UnsafePointer<CChar> {
    enum StaticStorage {
        static var buffer: UnsafeMutableBufferPointer<CChar> =
            .allocate(capacity: 255)
    }

    let hStdIn: HANDLE = GetStdHandle(STD_INPUT_HANDLE)
    if hStdIn == INVALID_HANDLE_VALUE {
        return UnsafePointer<CChar>(StaticStorage.buffer.baseAddress!)
    }

    var dwMode: DWORD = 0
    guard GetConsoleMode(hStdIn, &dwMode) else {
        return UnsafePointer<CChar>(StaticStorage.buffer.baseAddress!)
    }

    print(prompt, terminator: "")

    guard SetConsoleMode(hStdIn, DWORD(ENABLE_LINE_INPUT)) else {
        return UnsafePointer<CChar>(StaticStorage.buffer.baseAddress!)
    }
    defer { SetConsoleMode(hStdIn, dwMode) }

    var dwNumberOfCharsRead: DWORD = 0
    _ = ReadConsoleA(
        hStdIn,
        StaticStorage.buffer.baseAddress,
        DWORD(StaticStorage.buffer.count),
        &dwNumberOfCharsRead,
        nil
    )
    return UnsafePointer<CChar>(StaticStorage.buffer.baseAddress!)
}
#endif

extension SwiftPackageRegistryTool {
    struct Login: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Log in to a registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The registry URL")
        var url: URL?

        var registryURL: URL? {
            self.url
        }

        @Option(help: "Username")
        var username: String?

        @Option(help: "Password")
        var password: String?

        @Option(help: "Access token")
        var token: String?

        @Flag(help: "Allow writing to netrc file without confirmation")
        var noConfirm: Bool = false

        private static let PLACEHOLDER_TOKEN_USER = "token"

        func run(_ swiftTool: SwiftTool) throws {
            // We need to be able to read/write credentials
            // Make sure credentials store is available before proceeding
            let authorizationProvider: AuthorizationProvider?
            do {
                authorizationProvider = try swiftTool.getRegistryAuthorizationProvider()
            } catch {
                throw ValidationError.invalidCredentialStore(error)
            }

            guard let authorizationProvider else {
                throw ValidationError.unknownCredentialStore
            }

            let configuration = try getRegistriesConfig(swiftTool)

            // compute and validate registry URL
            guard let registryURL = self.registryURL ?? configuration.configuration.defaultRegistry?.url else {
                throw ValidationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

            guard let host = registryURL.host?.lowercased() else {
                throw ValidationError.invalidURL(registryURL)
            }

            let authenticationType: RegistryConfiguration.AuthenticationType
            let storeUsername: String
            let storePassword: String
            var saveChanges = true

            if let username {
                authenticationType = .basic

                storeUsername = username
                if let password {
                    // User provided password
                    storePassword = password
                } else if let stored = authorizationProvider.authentication(for: registryURL),
                          stored.user == storeUsername
                {
                    // Password found in credential store
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
                if let token {
                    // User provided token
                    storePassword = token
                } else if let stored = authorizationProvider.authentication(for: registryURL),
                          stored.user == storeUsername
                {
                    // Token found in credential store
                    storePassword = stored.password
                    saveChanges = false
                } else {
                    // Prompt user for token
                    storePassword = String(cString: getpass("Enter access token: "))
                }
            }

            let authorizationWriter = authorizationProvider as? AuthorizationWriter
            if saveChanges, authorizationWriter == nil {
                throw StringError("Credential store must be writable")
            }

            // Save in cache so we can try the credentials and persist to storage only if login succeeds
            try tsc_await { callback in
                authorizationWriter?.addOrUpdate(
                    for: registryURL,
                    user: storeUsername,
                    password: storePassword,
                    persist: false,
                    callback: callback
                )
            }

            // `url` can either be base URL of the registry, in which case the login API
            // is assumed to be at /login, or the full URL of the login API.
            var loginAPIPath: String?
            if !registryURL.path.isEmpty, registryURL.path != "/" {
                loginAPIPath = registryURL.path
            }

            // Login URL must be HTTPS
            guard let loginURL = URL(string: "https://\(host)\(loginAPIPath ?? "/login")") else {
                throw ValidationError.invalidURL(registryURL)
            }

            // Build a RegistryConfiguration with the given authentication settings
            var registryConfiguration = configuration.configuration
            registryConfiguration
                .registryAuthentication[host] = .init(type: authenticationType, loginAPIPath: loginAPIPath)

            // Build a RegistryClient to test login credentials (fingerprints don't matter in this case)
            let registryClient = RegistryClient(
                configuration: registryConfiguration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                skipSignatureValidation: false,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: authorizationProvider,
                delegate: .none,
                checksumAlgorithm: SHA256()
            )

            // Try logging in
            try tsc_await { callback in
                registryClient.login(
                    loginURL: loginURL,
                    timeout: .seconds(5),
                    observabilityScope: swiftTool.observabilityScope,
                    callbackQueue: .sharedConcurrent,
                    completion: callback
                )
            }
            print("Login successful.")

            // Login successful. Persist credentials to storage.

            let osStore = !(authorizationWriter is NetrcAuthorizationProvider)

            // Prompt if writing to netrc file and --no-confirm is not set
            if saveChanges, !osStore, !self.noConfirm {
                if self.globalOptions.security.forceNetrc {
                    print("""

                    WARNING: You choose to use netrc file instead of the operating system's secure credential store.
                    Your credentials will be written out to netrc file.
                    """)
                } else {
                    print("""

                    WARNING: Secure credential store is not supported on this platform.
                    Your credentials will be written out to netrc file.
                    """)
                }
                print("Continue? (Yes/No): ")
                guard readLine(strippingNewline: true)?.lowercased() == "yes" else {
                    print("Credentials not saved. Exiting...")
                    return
                }
            }

            if saveChanges {
                try tsc_await { callback in
                    authorizationWriter?.addOrUpdate(
                        for: registryURL,
                        user: storeUsername,
                        password: storePassword,
                        persist: true,
                        callback: callback
                    )
                }

                if osStore {
                    print("\nCredentials have been saved to the operating system's secure credential store.")
                } else {
                    print("\nCredentials have been saved to netrc file.")
                }
            }

            // Update user-level registry configuration file
            let update: (inout RegistryConfiguration) throws -> Void = { configuration in
                configuration.registryAuthentication[host] = .init(type: authenticationType, loginAPIPath: loginAPIPath)
            }
            try configuration.updateShared(with: update)

            print("Registry configuration updated.")
        }
    }

    struct Logout: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Log out from a registry"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The registry URL")
        var url: URL?

        var registryURL: URL? {
            self.url
        }

        func run(_ swiftTool: SwiftTool) throws {
            let configuration = try getRegistriesConfig(swiftTool)

            // compute and validate registry URL
            guard let registryURL = self.registryURL ?? configuration.configuration.defaultRegistry?.url else {
                throw ValidationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

            guard let host = registryURL.host?.lowercased() else {
                throw ValidationError.invalidURL(registryURL)
            }

            // We need to be able to read/write credentials
            guard let authorizationProvider = try swiftTool.getRegistryAuthorizationProvider() else {
                throw ValidationError.unknownCredentialStore
            }

            let authorizationWriter = authorizationProvider as? AuthorizationWriter
            let osStore = !(authorizationWriter is NetrcAuthorizationProvider)

            // Only OS credential store supports deletion
            if osStore {
                try tsc_await { callback in authorizationWriter?.remove(for: registryURL, callback: callback) }
                print("Credentials have been removed from operating system's secure credential store.")
            } else {
                print("netrc file not updated. Please remove credentials from the file manually.")
            }

            // Update user-level registry configuration file
            let update: (inout RegistryConfiguration) throws -> Void = { configuration in
                configuration.registryAuthentication.removeValue(forKey: host)
            }
            try configuration.updateShared(with: update)

            print("Registry configuration updated.")
            print("Logout successful.")
        }
    }
}
