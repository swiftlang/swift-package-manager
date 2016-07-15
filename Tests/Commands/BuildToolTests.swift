/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Commands

final class BuildToolTests: XCTestCase {
    func testUsage() throws {
        XCTAssert(try SwiftPMProduct.SwiftBuild.execute(["--help"], printIfError: true).contains("USAGE: swift build"))
    }

    func testVersion() throws {
        XCTAssert(try SwiftPMProduct.SwiftBuild.execute(["--version"], printIfError: true).contains("Swift Package Manager"))
    }

    func testBuildAndClean() throws {
        mktmpdir { path in
            // Create a known directory.
            let packageRoot = path.appending("Foo")
            try localFileSystem.createDirectory(packageRoot)

            // Run package init.
            _ = try SwiftPMProduct.SwiftPackage.execute(["init", "--type=executable"], chdir: packageRoot, printIfError: true)

            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(".build/debug/Foo"))
            XCTAssert(packageRoot.appending(".build").asString.isDirectory)

            // Clean, and check for removal.
            _ = try SwiftPMProduct.SwiftBuild.execute(["--clean"], chdir: packageRoot, printIfError: true)
            XCTAssert(!packageRoot.appending(".build/debug/Foo").asString.isFile)
            XCTAssert(!packageRoot.appending(".build").asString.isDirectory)

            // Clean again to ensure we get no error.
            _ = try SwiftPMProduct.SwiftBuild.execute(["--clean"], chdir: packageRoot, printIfError: true)
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testBuildAndClean", testBuildAndClean),
    ]
}
