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

import PackageModel
import PackageLoading

class ToolsVersionTests: XCTestCase {

    let loader = ToolsVersionLoader()

    func testBasics() throws {
        mktmpdir { path in
            let file = path.appending(component: ToolsVersion.toolsVersionFileName)

            // Test when file is not present.
            var toolsVersion = try loader.load(at: path, fileSystem: localFileSystem)
            XCTAssertEqual(toolsVersion, ToolsVersion.defaultToolsVersion)

            // Empty contents.
            try localFileSystem.writeFileContents(file, bytes: "")

            toolsVersion = try loader.load(at: path, fileSystem: localFileSystem)
            XCTAssertEqual(toolsVersion, ToolsVersion.defaultToolsVersion)

            // Malformed contents.
            try localFileSystem.writeFileContents(file, bytes: ByteString([0xFF,0xFF]))
            XCTAssertThrows(ToolsVersionLoader.Error.malformed(file: file)) {
                _ = try loader.load(at: path, fileSystem: localFileSystem)
            }

            // A valid version.
            try localFileSystem.writeFileContents(file, bytes: "3.1.0")
            toolsVersion = try loader.load(at: path, fileSystem: localFileSystem)
            XCTAssertEqual(toolsVersion, try ToolsVersion(string: "3.1.0"))

            // A valid toolchain.
            try localFileSystem.writeFileContents(file, bytes: "swift-3.1-toolchain")
            // FIXME: We can't load this yet.
            XCTAssertThrows(ToolsVersionLoader.Error.unknown) {
                _ = try loader.load(at: path, fileSystem: localFileSystem)
            }

            // A valid future version.
            try localFileSystem.writeFileContents(file, bytes: "4.0.0")
            toolsVersion = try loader.load(at: path, fileSystem: localFileSystem)
            // FIXME: Figure out what to do here?
            XCTAssertEqual(toolsVersion, try ToolsVersion(string: "4.0.0"))
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
