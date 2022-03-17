//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
import SPMTestSupport
import TSCBasic
import TSCUtility
import Workspace
import XCTest

final class AuthorizationConfigurationTests: XCTestCase {
    func testNetrcAuthorizationProviders() throws {
        let observability = ObservabilitySystem.makeForTesting()

        // custom .netrc file

        do {
            let fileSystem = InMemoryFileSystem()

            let customPath = fileSystem.homeDirectory.appending(components: UUID().uuidString, "custom-netrc-file")
            try fileSystem.createDirectory(customPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(customPath) {
                "machine mymachine.labkey.org login custom@labkey.org password custom"
            }

            let configuration = Workspace.Configuration.Authorization(netrc: .custom(customPath), keychain: .disabled)
            let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
            let netrcProviders = authorizationProvider?.providers.compactMap{ $0 as? NetrcAuthorizationProvider }

            XCTAssertEqual(netrcProviders?.count, 1)
            XCTAssertEqual(netrcProviders?.first.map { resolveSymlinks($0.path) }, resolveSymlinks(customPath))

            let auth = authorizationProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
            XCTAssertEqual(auth?.user, "custom@labkey.org")
            XCTAssertEqual(auth?.password, "custom")

            // delete it
            try fileSystem.removeFileTree(customPath)
            XCTAssertThrowsError(try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope), "error expected") { error in
                XCTAssertEqual(error as? StringError, StringError("Did not find .netrc file at \(customPath)."))
            }
        }

        // user .netrc file

        do {
            let fileSystem = InMemoryFileSystem()

            let userPath = fileSystem.homeDirectory.appending(component: ".netrc")
            try fileSystem.createDirectory(userPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(userPath) {
                "machine mymachine.labkey.org login user@labkey.org password user"
            }

            let configuration = Workspace.Configuration.Authorization(netrc: .user, keychain: .disabled)
            let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
            let netrcProviders = authorizationProvider?.providers.compactMap{ $0 as? NetrcAuthorizationProvider }

            XCTAssertEqual(netrcProviders?.count, 1)
            XCTAssertEqual(netrcProviders?.first.map { resolveSymlinks($0.path) }, resolveSymlinks(userPath))

            let auth = authorizationProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
            XCTAssertEqual(auth?.user, "user@labkey.org")
            XCTAssertEqual(auth?.password, "user")

            // delete it
            do {
                try fileSystem.removeFileTree(userPath)
                let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope)  as? CompositeAuthorizationProvider
                XCTAssertNil(authorizationProvider)
            }
        }

        // workspace + user .netrc file

        do {
            let fileSystem = InMemoryFileSystem()

            let userPath = fileSystem.homeDirectory.appending(component: ".netrc")
            try fileSystem.createDirectory(userPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(userPath) {
                "machine mymachine.labkey.org login user@labkey.org password user"
            }

            let workspacePath = AbsolutePath.root.appending(components: UUID().uuidString, ".netrc")
            try fileSystem.createDirectory(workspacePath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(workspacePath) {
                "machine mymachine.labkey.org login workspace@labkey.org password workspace"
            }

            let configuration = Workspace.Configuration.Authorization(netrc: .workspaceAndUser(rootPath: workspacePath.parentDirectory), keychain: .disabled)
            let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
            let netrcProviders = authorizationProvider?.providers.compactMap{ $0 as? NetrcAuthorizationProvider }

            XCTAssertEqual(netrcProviders?.count, 2)
            XCTAssertEqual(netrcProviders?.first.map { resolveSymlinks($0.path) }, resolveSymlinks(workspacePath))
            XCTAssertEqual(netrcProviders?.last.map { resolveSymlinks($0.path) }, resolveSymlinks(userPath))

            let auth = authorizationProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
            XCTAssertEqual(auth?.user, "workspace@labkey.org")
            XCTAssertEqual(auth?.password, "workspace")

            // delete workspace file
            do {
                try fileSystem.removeFileTree(workspacePath)
                let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
                let auth = authorizationProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "user@labkey.org")
                XCTAssertEqual(auth?.password, "user")
            }

            // delete user file
            do {
                try fileSystem.removeFileTree(userPath)
                let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? CompositeAuthorizationProvider
                XCTAssertNil(authorizationProvider)
            }
        }
    }
}
