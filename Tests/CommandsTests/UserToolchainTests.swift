/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import TestSupport
@testable import Commands

final class UserToolchainTests: XCTestCase {

    func testExecutableLookup() throws {
        mktmpdir { path in

            let pathEnv1 = path.appending(component: "pathEnv1")
            try localFileSystem.createDirectory(pathEnv1)
            let pathEnvClang = pathEnv1.appending(component: "clang")
            try localFileSystem.writeFileContents(pathEnvClang, bytes: "")
            let pathEnv = [path.appending(component: "pathEnv2"), pathEnv1]

            // nil and empty string should fail.
            XCTAssertNil(UserToolchain.lookupExecutablePath(inEnvValue: nil, currentWorkingDirectory: path, searchPaths: pathEnv))
            XCTAssertNil(UserToolchain.lookupExecutablePath(inEnvValue: "", currentWorkingDirectory: path, searchPaths: pathEnv))

            // Absolute path to a binary should return it.
            var exec = UserToolchain.lookupExecutablePath(inEnvValue: pathEnvClang.asString, currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)

            // This should lookup from PATH variable since executable is not present in cwd.
            exec = UserToolchain.lookupExecutablePath(inEnvValue: "clang", currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)

            // Create the binary relative to cwd.
            let clang = path.appending(component: "clang")
            try localFileSystem.writeFileContents(clang, bytes: "")
            // We should now find clang which is in cwd.
            exec = UserToolchain.lookupExecutablePath(inEnvValue: "clang", currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, clang)
        }
    }

    func testEnvSearchPaths() throws {
        let cwd = AbsolutePath("/dummy")
        let paths = UserToolchain.getEnvSearchPaths(pathString: "something:.:abc/../.build/debug:/usr/bin:/bin/", currentWorkingDirectory: cwd)
        XCTAssertEqual(paths, ["/dummy/something", "/dummy", "/dummy/.build/debug", "/usr/bin", "/bin"].map(AbsolutePath.init))
    }

    static var allTests = [
        ("testExecutableLookup", testExecutableLookup),
        ("testEnvSearchPaths", testEnvSearchPaths),
    ]
}
