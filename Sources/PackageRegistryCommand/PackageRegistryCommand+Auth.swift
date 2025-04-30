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
import PackageFingerprint
import PackageModel
import PackageRegistry
import PackageSigning
import Workspace

import struct TSCBasic.SHA256

#if os(Windows)
import WinSDK

private func readpassword(_ prompt: String) throws -> String {
    enum StaticStorage {
        static var buffer: UnsafeMutableBufferPointer<CChar> =
            .allocate(capacity: PackageRegistryCommand.Login.passwordBufferSize)
    }

    let hStdIn: HANDLE = GetStdHandle(STD_INPUT_HANDLE)
    if hStdIn == INVALID_HANDLE_VALUE {
        throw StringError("unable to read input: GetStdHandle returns INVALID_HANDLE_VALUE")
    }

    var dwMode: DWORD = 0
    guard GetConsoleMode(hStdIn, &dwMode) else {
        throw StringError("unable to read input: GetConsoleMode failed")
    }

    print(prompt, terminator: "")

    guard SetConsoleMode(hStdIn, DWORD(ENABLE_LINE_INPUT)) else {
        throw StringError("unable to read input: SetConsoleMode failed")
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

    let password = String(cString: UnsafePointer<CChar>(StaticStorage.buffer.baseAddress!))
    guard password.count <= PackageRegistryCommand.Login.maxPasswordLength else {
        throw PackageRegistryCommand.ValidationError
            .credentialLengthLimitExceeded(PackageRegistryCommand.Login.maxPasswordLength)
    }
    return password
}
#else
#if canImport(Android)
import Android
#endif

private func readpassword(_ prompt: String) throws -> String {
    let password: String

    #if canImport(Darwin)
    var buffer = [CChar](repeating: 0, count: PackageRegistryCommand.Login.passwordBufferSize)
    password = try withExtendedLifetime(buffer) {
        guard let passwordPtr = readpassphrase(prompt, &buffer, buffer.count, 0) else {
            throw StringError("unable to read input")
        }

        return String(cString: passwordPtr)
    }
    #else
    // GNU C implementation of getpass has no limit on the password length
    // (https://man7.org/linux/man-pages/man3/getpass.3.html)
    password = String(cString: getpass(prompt))
    #endif

    guard password.count <= PackageRegistryCommand.Login.maxPasswordLength else {
        throw PackageRegistryCommand.ValidationError
            .credentialLengthLimitExceeded(PackageRegistryCommand.Login.maxPasswordLength)
    }
    return password
}
#endif

extension PackageRegistryCommand {
    struct Login: AsyncSwiftCommand {

        static func loginURL(from registryURL: URL, loginAPIPath: String?) throws -> URL {
            // Login URL must be HTTPS
            var loginURLComponents = URLComponents(url: registryURL, resolvingAgainstBaseURL: true)
            loginURLComponents?.scheme = "https"
            loginURLComponents?.path = loginAPIPath ?? "/login"

            guard let loginURL = loginURLComponents?.url else {
                throw ValidationError.invalidURL(registryURL)
            }

            return loginURL
        }

        static let configuration = CommandConfiguration(
            abstract: "Log in to a registry"
        )

        static let maxPasswordLength = 512
        // Define a larger buffer size so we read more than allowed, and
        // this way we can tell if the entered password is over the length
        // limit. One space is for \0, another is for the "overflowing" char.
        static let passwordBufferSize = Self.maxPasswordLength + 2

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

        @Option(
            name: .customLong("token-file"),
            help: "Path to the file containing access token"
        )
        var tokenFilePath: AbsolutePath?

        @Flag(help: "Allow writing to netrc file without confirmation")
        var noConfirm: Bool = false

        private static let PLACEHOLDER_TOKEN_USER = "token"

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            // We need to be able to read/write credentials
            // Make sure credentials store is available before proceeding
            let authorizationProvider: AuthorizationProvider?
            do {
                authorizationProvider = try swiftCommandState.getRegistryAuthorizationProvider()
            } catch {
                throw ValidationError.invalidCredentialStore(error)
            }

            guard let authorizationProvider else {
                throw ValidationError.unknownCredentialStore
            }

            // Auth config is in user-level registries config only
            let configuration = try getRegistriesConfig(swiftCommandState, global: true)

            // compute and validate registry URL
            guard let registryURL = self.registryURL ?? configuration.configuration.defaultRegistry?.url else {
                throw ValidationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

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
                    storePassword = try readpassword("Enter password for '\(storeUsername)': ")
                }
            } else {
                authenticationType = .token

                // All token auth accounts have the same placeholder value
                storeUsername = Self.PLACEHOLDER_TOKEN_USER
                if let token {
                    // User provided token
                    storePassword = token
                } else if let tokenFilePath {
                    print("Reading access token from \(tokenFilePath).")
                    storePassword = try localFileSystem.readFileContents(tokenFilePath)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let stored = authorizationProvider.authentication(for: registryURL),
                          stored.user == storeUsername
                {
                    // Token found in credential store
                    storePassword = stored.password
                    saveChanges = false
                } else {
                    // Prompt user for token
                    storePassword = try readpassword("Enter access token: ")
                }
            }

            let authorizationWriter = authorizationProvider as? AuthorizationWriter
            if saveChanges, authorizationWriter == nil {
                throw StringError("Credential store must be writable")
            }

            // Save in cache so we can try the credentials and persist to storage only if login succeeds
            try await authorizationWriter?.addOrUpdate(
                for: registryURL,
                user: storeUsername,
                password: storePassword,
                persist: false
            )

            // `url` can either be base URL of the registry, in which case the login API
            // is assumed to be at /login, or the full URL of the login API.
            var loginAPIPath: String?
            if !registryURL.path.isEmpty, registryURL.path != "/" {
                loginAPIPath = registryURL.path
            }

            let loginURL = try Self.loginURL(from: registryURL, loginAPIPath: loginAPIPath)


            // Build a RegistryConfiguration with the given authentication settings
            var registryConfiguration = configuration.configuration
            try registryConfiguration.add(authentication: .init(type: authenticationType, loginAPIPath: loginAPIPath), for: registryURL)

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
            try await registryClient.login(
                loginURL: loginURL,
                timeout: .seconds(5),
                observabilityScope: swiftCommandState.observabilityScope
            )

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
                try await authorizationWriter?.addOrUpdate(
                    for: registryURL,
                    user: storeUsername,
                    password: storePassword,
                    persist: true
                )

                if osStore {
                    print("\nCredentials have been saved to the operating system's secure credential store.")
                } else {
                    print("\nCredentials have been saved to netrc file.")
                }
            }

            // Update user-level registry configuration file
            let update: (inout RegistryConfiguration) throws -> Void = { configuration in
                try configuration.add(authentication: .init(type: authenticationType, loginAPIPath: loginAPIPath), for: registryURL)
            }
            try configuration.updateShared(with: update)

            print("Registry configuration updated.")
        }
    }

    struct Logout: AsyncSwiftCommand {
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

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            // Auth config is in user-level registries config only
            let configuration = try getRegistriesConfig(swiftCommandState, global: true)

            // compute and validate registry URL
            guard let registryURL = self.registryURL ?? configuration.configuration.defaultRegistry?.url else {
                throw ValidationError.unknownRegistry
            }

            try registryURL.validateRegistryURL()

            // We need to be able to read/write credentials
            guard let authorizationProvider = try swiftCommandState.getRegistryAuthorizationProvider() else {
                throw ValidationError.unknownCredentialStore
            }

            let authorizationWriter = authorizationProvider as? AuthorizationWriter
            let osStore = !(authorizationWriter is NetrcAuthorizationProvider)

            // Only OS credential store supports deletion
            if osStore {
                try await authorizationWriter?.remove(for: registryURL)
                print("Credentials have been removed from operating system's secure credential store.")
            } else {
                print("netrc file not updated. Please remove credentials from the file manually.")
            }

            // Update user-level registry configuration file
            let update: (inout RegistryConfiguration) throws -> Void = { configuration in
                configuration.removeAuthentication(for: registryURL)
            }
            try configuration.updateShared(with: update)

            print("Registry configuration updated.")
            print("Logout successful.")
        }
    }
}
