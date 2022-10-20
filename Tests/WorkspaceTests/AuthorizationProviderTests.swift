//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
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

final class AuthorizationProviderTests: XCTestCase {
    func testNetrcAuthorizationProviders() throws {
        let observability = ObservabilitySystem.makeForTesting()

        // custom .netrc file

        do {
            let fileSystem = InMemoryFileSystem()

            let customPath = try fileSystem.homeDirectory.appending(components: UUID().uuidString, "custom-netrc-file")
            try fileSystem.createDirectory(customPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(customPath) {
                "machine mymachine.labkey.org login custom@labkey.org password custom"
            }

            let configuration = Workspace.Configuration.Authorization(netrc: .custom(customPath), keychain: .disabled)
            let netrcProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? NetrcAuthorizationProvider

            XCTAssertNotNil(netrcProvider)
            XCTAssertEqual(try netrcProvider.map { try resolveSymlinks($0.path) }, try resolveSymlinks(customPath))

            let auth = netrcProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
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

            let userPath = try fileSystem.homeDirectory.appending(component: ".netrc")
            try fileSystem.createDirectory(userPath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(userPath) {
                "machine mymachine.labkey.org login user@labkey.org password user"
            }

            let configuration = Workspace.Configuration.Authorization(netrc: .user, keychain: .disabled)
            let netrcProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? NetrcAuthorizationProvider

            XCTAssertNotNil(netrcProvider)
            XCTAssertEqual(try netrcProvider.map { try resolveSymlinks($0.path) }, try resolveSymlinks(userPath))

            let auth = netrcProvider?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
            XCTAssertEqual(auth?.user, "user@labkey.org")
            XCTAssertEqual(auth?.password, "user")

            // delete it
            do {
                try fileSystem.removeFileTree(userPath)
                let authorizationProvider = try configuration.makeAuthorizationProvider(fileSystem: fileSystem, observabilityScope: observability.topScope) as? NetrcAuthorizationProvider
                XCTAssertNil(authorizationProvider)
            }
        }
    }
}
