/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TestSupport
import Basic
@testable import Utility

class miscTests: XCTestCase {
    func testClangVersionOutput() {
        var versionOutput = ""
        XCTAssert(getClangVersion(versionOutput: versionOutput) == nil)

        versionOutput = "some - random - string"
        XCTAssert(getClangVersion(versionOutput: versionOutput) == nil)

        versionOutput = "Ubuntu clang version 3.6.0-2ubuntu1~trusty1 (tags/RELEASE_360/final) (based on LLVM 3.6.0)"
        XCTAssert(getClangVersion(versionOutput: versionOutput) ?? (0, 0) == (3, 6))

        versionOutput = "Ubuntu clang version 2.4-1ubuntu3 (tags/RELEASE_34/final) (based on LLVM 3.4)"
        XCTAssert(getClangVersion(versionOutput: versionOutput) ?? (0, 0) == (2, 4))
    }

    func testVersion() throws {
        // Valid.
        XCTAssertEqual(Version(string: "0.9.21-alpha.beta+1011"), Version(0,9,21, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011"))
        XCTAssertEqual(Version(string: "0.9.21+1011"), Version(0,9,21, prereleaseIdentifiers: [], buildMetadataIdentifier: "1011"))
        XCTAssertEqual(Version(string: "01.002.0003"), Version(1,2,3))
        XCTAssertEqual(Version(string: "0.9.21"), Version(0,9,21))

        // Invalid.
        let invalidVersions = ["foo", "1", "1.0", "1.0.", "1.0.0."]
        for v in invalidVersions {
            XCTAssertTrue(Version(string: v) == nil)
        }
    }

    func testExecutableLookup() throws {
        mktmpdir { path in
            
            let pathEnv1 = path.appending(component: "pathEnv1")
            try localFileSystem.createDirectory(pathEnv1)
            let pathEnvClang = pathEnv1.appending(component: "clang")
            try localFileSystem.writeFileContents(pathEnvClang, bytes: "")
            let pathEnv = [path.appending(component: "pathEnv2"), pathEnv1]
            
            // nil and empty string should fail.
            XCTAssertNil(lookupExecutablePath(filename: nil, currentWorkingDirectory: path, searchPaths: pathEnv))
            XCTAssertNil(lookupExecutablePath(filename: "", currentWorkingDirectory: path, searchPaths: pathEnv))
            
            // Absolute path to a binary should return it.
            var exec = lookupExecutablePath(filename: pathEnvClang.asString, currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)
            
            // This should lookup from PATH variable since executable is not present in cwd.
            exec = lookupExecutablePath(filename: "clang", currentWorkingDirectory: path, searchPaths: pathEnv)
            XCTAssertEqual(exec, pathEnvClang)
            
            // Create the binary relative to cwd.
            let clang = path.appending(component: "clang")
            try localFileSystem.writeFileContents(clang, bytes: "")
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
        ("testClangVersionOutput", testClangVersionOutput),
        ("testVersion", testVersion),
        ("testExecutableLookup", testExecutableLookup),
        ("testEnvSearchPaths", testEnvSearchPaths),
        ("testEmptyEnvSearchPaths", testEnvSearchPaths),
    ]
}
