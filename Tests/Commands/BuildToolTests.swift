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
    private func execute(_ args: [String], chdir: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftBuild.execute(args, chdir: chdir, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift build"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
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
            XCTAssert(try! isDirectory(packageRoot.appending(".build")))

            // Clean, and check for removal.
            _ = try execute(["--clean"], chdir: packageRoot)
            XCTAssert(try! !isFile(packageRoot.appending(".build/debug/Foo")))
            XCTAssert(try! !isDirectory(packageRoot.appending(".build")))

            // Clean again to ensure we get no error.
            _ = try execute(["--clean"], chdir: packageRoot)
        }
    }

    func testCleanDist() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending("Bar")
            
            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(".build/debug/Bar"))
            XCTAssert(packageRoot.appending(".build").asString.isDirectory)
            XCTAssert(packageRoot.appending("Packages").asString.isDirectory)

            // Clean, and check for removal of the build directory but not Packages.
            _ = try execute(["--clean"], chdir: packageRoot)
            XCTAssert(!packageRoot.appending(".build").asString.isDirectory)
            XCTAssert(packageRoot.appending("Packages").asString.isDirectory)

            // Fully clean, and check for removal of both.
            _ = try execute(["--clean=dist"], chdir: packageRoot)
            XCTAssert(!packageRoot.appending(".build").asString.isDirectory)
            XCTAssert(!packageRoot.appending("Packages").asString.isDirectory)
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testBuildAndClean", testBuildAndClean),
        ("testCleanDist", testCleanDist),
    ]
}
