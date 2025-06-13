//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
import _InternalTestSupport
import Workspace
import Testing

fileprivate struct AuthorizationProviderTests {
    @Test
    func netrcAuthorizationProviders() throws {
        let observability = ObservabilitySystem.makeForTesting()

        // custom .netrc file
        do {
            let fileSystem: FileSystem = InMemoryFileSystem()

            let customPath = try fileSystem.homeDirectory.appending(components: UUID().uuidString, "custom-netrc-file")
            try fileSystem.createDirectory(customPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                customPath,
                string: "machine mymachine.labkey.org login custom@labkey.org password custom"
            )

            let configuration = Workspace.Configuration.Authorization(netrc: .custom(customPath), keychain: .disabled)
            let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
            let netrcProviders = try #require(authorizationProvider?.providers.compactMap { $0 as? NetrcAuthorizationProvider })

            let expectedNetrcProvider = try resolveSymlinks(customPath)
            #expect(netrcProviders.count == 1)
            #expect(try netrcProviders.first.map { try resolveSymlinks($0.path) } == expectedNetrcProvider)

            let auth = try #require(authorizationProvider?.authentication(for: "https://mymachine.labkey.org"))
            #expect(auth.user == "custom@labkey.org")
            #expect(auth.password == "custom")

            // delete it
            try fileSystem.removeFileTree(customPath)
            #expect(throws: StringError("Did not find netrc file at \(customPath).")) {
                try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope)
            }
        }

        // user .netrc file
        do {
            let fileSystem = InMemoryFileSystem()

            let userPath = try fileSystem.homeDirectory.appending(".netrc")
            try fileSystem.createDirectory(userPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                userPath,
                string: "machine mymachine.labkey.org login user@labkey.org password user"
            )

            let configuration = Workspace.Configuration.Authorization(netrc: .user, keychain: .disabled)
            let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
            let netrcProviders = try #require(authorizationProvider?.providers.compactMap { $0 as? NetrcAuthorizationProvider })

            let expectedNetrcProvider = try resolveSymlinks(userPath)
            #expect(netrcProviders.count == 1)
            #expect(try netrcProviders.first.map { try resolveSymlinks($0.path) } == expectedNetrcProvider)

            let auth = try #require(authorizationProvider?.authentication(for: "https://mymachine.labkey.org"))
            #expect(auth.user == "user@labkey.org")
            #expect(auth.password == "user")

            // delete it
            do {
                try fileSystem.removeFileTree(userPath)
                let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
                #expect(authorizationProvider == nil)
            }
        }
    }

    @Test
    func registryNetrcAuthorizationProviders() throws {
        let observability = ObservabilitySystem.makeForTesting()

        // custom .netrc file

        do {
            let fileSystem: FileSystem = InMemoryFileSystem()

            let customPath = try fileSystem.homeDirectory.appending(components: UUID().uuidString, "custom-netrc-file")
            try fileSystem.createDirectory(customPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                customPath,
                string: "machine mymachine.labkey.org login custom@labkey.org password custom"
            )

            let configuration = Workspace.Configuration.Authorization(netrc: .custom(customPath), keychain: .disabled)
            let netrcProvider = try configuration.makeRegistryAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? NetrcAuthorizationProvider

            let expectedNetrcProvider = try resolveSymlinks(customPath)
            #expect(netrcProvider != nil)
            #expect(try netrcProvider.map { try resolveSymlinks($0.path) } == expectedNetrcProvider)

            let auth = try #require(netrcProvider?.authentication(for: "https://mymachine.labkey.org"))
            #expect(auth.user == "custom@labkey.org")
            #expect(auth.password == "custom")

            // delete it
            try fileSystem.removeFileTree(customPath)
            #expect(throws: StringError("did not find netrc file at \(customPath)")) {
                try configuration.makeRegistryAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope)
            }
        }

        // user .netrc file

        do {
            let fileSystem = InMemoryFileSystem()

            let userPath = try fileSystem.homeDirectory.appending(".netrc")
            try fileSystem.createDirectory(userPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(
                userPath,
                string: "machine mymachine.labkey.org login user@labkey.org password user"
            )

            let configuration = Workspace.Configuration.Authorization(netrc: .user, keychain: .disabled)
            let netrcProvider = try configuration.makeRegistryAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? NetrcAuthorizationProvider

            let expectedNetrcProvider = try resolveSymlinks(userPath)
            #expect(netrcProvider != nil)
            #expect(try netrcProvider.map { try resolveSymlinks($0.path) } == expectedNetrcProvider)

            let auth = try #require(netrcProvider?.authentication(for: "https://mymachine.labkey.org"))
            #expect(auth.user == "user@labkey.org")
            #expect(auth.password == "user")

            // delete it
            do {
                try fileSystem.removeFileTree(userPath)
                let authorizationProviderOpt =
                    try configuration.makeRegistryAuthorizationProvider(
                        fileSystem: fileSystem,
                        observabilityScope: observability.topScope,
                    ) as? NetrcAuthorizationProvider
                // Even if user .netrc file doesn't exist, the provider will be non-nil but contain no data.
                let expectedAuthorizationProvider = try resolveSymlinks(userPath)
                let authorizationProvider: NetrcAuthorizationProvider = try #require(
                    authorizationProviderOpt)
                #expect(authorizationProvider.path == expectedAuthorizationProvider)
                #expect(authorizationProvider.machines.isEmpty)
            }
        }
    }
}
