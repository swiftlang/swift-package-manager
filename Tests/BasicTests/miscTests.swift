/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TestSupport
@testable import Basic

class miscTests: XCTestCase {

    func testExecutableLookup() throws {
        mktmpdir { path in
            
            let pathEnv1 = path.appending(component: "pathEnv1")
            try localFileSystem.createDirectory(pathEnv1)
            let pathEnvClang = pathEnv1.appending(component: "clang")
            try localFileSystem.writeFileContents(pathEnvClang, bytes: "")
            let pathEnv = [path.appending(component: "pathEnv2"), pathEnv1]

            try! Process.checkNonZeroExit(args: "chmod", "+x", pathEnvClang.asString)

            // nil and empty string should fail.
            XCTAssertNil(lookupExecutablePath(filename: nil, currentWorkingDirectory: path, searchPaths: pathEnv))
            XCTAssertNil(lookupExecutablePath(filename: "", currentWorkingDirectory: path, searchPaths: pathEnv))
            
            // Absolute path to a binary should return it.
            var exec = lookupExecutablePath(filename: pathEnvClang.asString, currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)
            
            // This should lookup from PATH variable since executable is not present in cwd.
            exec = lookupExecutablePath(filename: "clang", currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)
            
            // Create the binary relative to cwd and make it executable.
            let clang = path.appending(component: "clang")
            try localFileSystem.writeFileContents(clang, bytes: "")
            try! Process.checkNonZeroExit(args: "chmod", "+x", clang.asString)
            // We should now find clang which is in cwd.
            exec = lookupExecutablePath(filename: "clang", currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, clang)
        }
    }
    
    func testEnvSearchPaths() throws {
        let cwd = AbsolutePath("/dummy")
        let paths = getEnvSearchPaths(pathString: "something:.:abc/../.build/debug:/usr/bin:/bin/", currentWorkingDirectory: cwd)
        XCTAssertEqual(paths, ["/dummy/something", "/dummy", "/dummy/.build/debug", "/usr/bin", "/bin"].map(AbsolutePath.init))
    }
    
    func testEmptyEnvSearchPaths() throws {
        let cwd = AbsolutePath("/dummy")
        let paths = getEnvSearchPaths(pathString: "", currentWorkingDirectory: cwd)
        XCTAssertEqual(paths, [])
        
        let nilPaths = getEnvSearchPaths(pathString: nil, currentWorkingDirectory: cwd)
        XCTAssertEqual(nilPaths, [])
    }

    static var allTests = [
        ("testExecutableLookup", testExecutableLookup),
        ("testEnvSearchPaths", testEnvSearchPaths),
        ("testEmptyEnvSearchPaths", testEnvSearchPaths),
    ]
}
