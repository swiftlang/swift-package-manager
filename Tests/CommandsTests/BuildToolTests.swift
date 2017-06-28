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
@testable import Commands

final class BuildToolTests: XCTestCase {
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["-help"]).contains("USAGE: swift build"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testBinPath() throws {
        fixture(name: "ValidLayouts/SingleModule/Executable") { path in
            let fullPath = resolveSymlinks(path)
            XCTAssertEqual(try execute(["--show-bin-path"], packagePath: fullPath),
                           fullPath.appending(RelativePath(".build/debug")).asString + "\n")
            XCTAssertEqual(try execute(["-c", "release", "--show-bin-path"], packagePath: fullPath),
                           fullPath.appending(RelativePath(".build/release")).asString + "\n")
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testBinPath", testBinPath),
    ]
}
