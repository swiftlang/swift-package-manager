/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Basics
@testable import Commands
import SPMTestSupport
import TSCBasic
import XCTest

final class SwiftToolTests: XCTestCase {
    func testNetrcAuthorizationProviders() throws {
        fixture(name: "DependencyResolution/External/XCFramework") { packageRoot in
            let fs = localFileSystem
            
            let localPath = packageRoot.appending(component: ".netrc")
            let userHomePath = fs.homeDirectory.appending(component: ".netrc")

            // custom .netrc file
            do {
                let customPath = fs.homeDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(customPath) {
                    "machine mymachine.labkey.org login custom@labkey.org password custom"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftTool(options: options)
                
                let netrcProviders = try tool.getNetrcAuthorizationProviders()
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(netrcProviders.first.map { resolveSymlinks($0.path) }, resolveSymlinks(customPath))

                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getNetrcAuthorizationProviders(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("Did not find .netrc file at \(customPath)."))
                }
            }

            // local .netrc file
            do {
                // make sure there isn't a user home one
                try localFileSystem.removeFileTree(userHomePath)
                
                try fs.writeFileContents(localPath) {
                    return "machine mymachine.labkey.org login local@labkey.org password local"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString])
                let tool = try SwiftTool(options: options)
                
                let netrcProviders = try tool.getNetrcAuthorizationProviders()
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(netrcProviders.first.map { resolveSymlinks($0.path) }, resolveSymlinks(localPath))

                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "local@labkey.org")
                XCTAssertEqual(auth?.password, "local")
            }

            // user .netrc file
            do {
                // make sure there isn't a local one
                try localFileSystem.removeFileTree(localPath)

                try fs.writeFileContents(userHomePath) {
                    return "machine mymachine.labkey.org login user@labkey.org password user"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString])
                let tool = try SwiftTool(options: options)

                let netrcProviders = try tool.getNetrcAuthorizationProviders()
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(netrcProviders.first.map { resolveSymlinks($0.path) }, resolveSymlinks(userHomePath))
                
                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "user@labkey.org")
                XCTAssertEqual(auth?.password, "user")
            }
            
            // both local and user .netrc file
            do {
                try fs.writeFileContents(localPath) {
                    return "machine mymachine.labkey.org login local@labkey.org password local"
                }
                try fs.writeFileContents(userHomePath) {
                    return "machine mymachine.labkey.org login user@labkey.org password user"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString])
                let tool = try SwiftTool(options: options)

                let netrcProviders = try tool.getNetrcAuthorizationProviders()
                XCTAssertEqual(netrcProviders.count, 2)
                XCTAssertEqual(netrcProviders.map { resolveSymlinks($0.path) }, [localPath, userHomePath].map(resolveSymlinks))
                
                // local before user .netrc file
                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "local@labkey.org")
                XCTAssertEqual(auth?.password, "local")
            }
        }
    }
}
