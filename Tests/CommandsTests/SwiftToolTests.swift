/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
@testable import Commands
import SPMTestSupport
import TSCBasic
import XCTest

final class SwiftToolTests: XCTestCase {
    func testNetrcLocations() throws {
        fixture(name: "DependencyResolution/External/XCFramework") { packageRoot in
            let fs = localFileSystem

            // custom .netrc file

            do {
                let customPath = fs.homeDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(customPath) {
                    "machine mymachine.labkey.org login custom@labkey.org password custom"
                }


                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftTool(options: options)
                XCTAssertEqual(try tool.getNetrcConfigFile().map(resolveSymlinks), resolveSymlinks(customPath))
                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getNetrcConfigFile(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("Did not find .netrc file at \(customPath)."))
                }
            }

            // local .netrc file

            do {
                let localPath = packageRoot.appending(component: ".netrc")
                try fs.writeFileContents(localPath) {
                    return "machine mymachine.labkey.org login local@labkey.org password local"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString])
                let tool = try SwiftTool(options: options)

                XCTAssertEqual(try tool.getNetrcConfigFile().map(resolveSymlinks), resolveSymlinks(localPath))
                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "local@labkey.org")
                XCTAssertEqual(auth?.password, "local")
            }

            // user .netrc file

            do {
                // make sure there isn't a local one
                try localFileSystem.removeFileTree(packageRoot.appending(component: ".netrc"))

                let userHomePath = fs.homeDirectory.appending(component: ".netrc")
                try fs.writeFileContents(userHomePath) {
                    return "machine mymachine.labkey.org login user@labkey.org password user"
                }

                let options = try SwiftToolOptions.parse(["--package-path", packageRoot.pathString])
                let tool = try SwiftTool(options: options)

                XCTAssertEqual(try tool.getNetrcConfigFile().map(resolveSymlinks), resolveSymlinks(userHomePath))
                let auth = try tool.getAuthorizationProvider()?.authentication(for: URL(string: "https://mymachine.labkey.org")!)
                XCTAssertEqual(auth?.user, "user@labkey.org")
                XCTAssertEqual(auth?.password, "user")
            }
        }
    }
}
