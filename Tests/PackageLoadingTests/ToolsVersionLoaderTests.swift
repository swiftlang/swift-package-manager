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
import Utility

class ToolsVersionLoaderTests: XCTestCase {

    let loader = ToolsVersionLoader()

    func load(_ bytes: ByteString, _ body: ((ToolsVersion) -> Void)? = nil) throws {
        let fs = InMemoryFileSystem()
        let path = AbsolutePath("/pkg/Package.swift")
        try! fs.createDirectory(path.parentDirectory, recursive: true)
        try! fs.writeFileContents(path, bytes: bytes)
        let toolsVersion = try loader.load(at: AbsolutePath("/pkg"), fileSystem: fs)
        body?(toolsVersion)
    }

    func testBasics() throws {

        let validVersions = [
            "// swift-tools-version:3.1"                : (3, 1, 0, "3.1.0"),
            "// swift-tools-version:3.1-dev"            : (3, 1, 0, "3.1.0"),
            "// swift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "// swift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "// swift-tools-version:3.1.2"              : (3, 1, 2, "3.1.2"),
            "// swift-tools-version:3.1.2;"             : (3, 1, 2, "3.1.2"),
            "// swift-tools-vErsion:3.1.2;;;;;"         : (3, 1, 2, "3.1.2"),
            "// swift-tools-version:3.1.2;x;x;x;x;x;"   : (3, 1, 2, "3.1.2"),
            "// swift-toolS-version:3.5.2;hello"        : (3, 5, 2, "3.5.2"),
            "// sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : (3, 5, 2, "3.5.2"),
        ]

        for (version, result) in validVersions {
            try load(ByteString(encodingAsUTF8: version)) { toolsVersion in
                XCTAssertEqual(toolsVersion.major, result.0)
                XCTAssertEqual(toolsVersion.minor, result.1)
                XCTAssertEqual(toolsVersion.patch, result.2)
                XCTAssertEqual(toolsVersion.description, result.3)
            }
        }


        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// swift-tools-version:3.1.0\n\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion.description, "3.1.0")
            }
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// swift-tools-version:3.1.0\n"
            stream <<< "// swift-tools-version:4.1.0\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion.description, "3.1.0")
            }
        }
    }

    func testNonMatching() throws {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// \n"
            stream <<< "// swift-tools-version:6.1.0\n"
            stream <<< "// swift-tools-version:4.1.0\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion, ToolsVersion.defaultToolsVersion)
            }
        }

        try load("// \n// swift-tools-version:6.1.0\n") { toolsVersion in
            XCTAssertEqual(toolsVersion, ToolsVersion.defaultToolsVersion)
        }

        assertFailure("//swift-tools-:6.1.0\n", "//swift-tools-:6.1.0")
        assertFailure("//swift-tool-version:6.1.0\n", "//swift-tool-version:6.1.0")
        assertFailure("//  swift-tool-version:6.1.0\n", "//  swift-tool-version:6.1.0")
        assertFailure("// swift-tool-version:6.1.0\n", "// swift-tool-version:6.1.0")
        assertFailure("noway// swift-tools-version:6.1.0\n", "noway// swift-tools-version:6.1.0")
        assertFailure("// swift-tool-version:2.1.0\n// swift-tools-version:6.1.0\n", "// swift-tool-version:2.1.0")

        assertFailure("// haha swift-tools-version:6.1.0\n", "// haha swift-tools-version:6.1.0")
        assertFailure("//// swift-tools-version:6.1.0\n", "//// swift-tools-version:6.1.0")
        assertFailure("// swift-tools-version 6.1.0\n", "// swift-tools-version 6.1.0")
        assertFailure("// swift-tOols-Version 6.1.0\n", "// swift-tOols-Version 6.1.0")
        assertFailure("// swift-tools-version:6.1.2.0\n", "6.1.2.0")
        assertFailure("// swift-tools-version:-1.1.2\n", "-1.1.2")
        assertFailure("// swift-tools-version:3.1hello", "3.1hello")
    }

    func testVersionSpecificManifest() throws {
        let fs = InMemoryFileSystem()
        let root = AbsolutePath("/pkg")
        try fs.createDirectory(root, recursive: true)

        /// Loads the tools version of root pkg.
        func load(_ body: (ToolsVersion) -> Void) {
            body(try! loader.load(at: root, fileSystem: fs))
        }

        // Test default manifest.
        try fs.writeFileContents(root.appending(component: "Package.swift"), bytes: "// swift-tools-version:3.1.1\n")
        load { version in
            XCTAssertEqual(version.description, "3.1.1")
        }

        // Test version specific manifests.
        let keys = Versioning.currentVersionSpecificKeys

        // In case the count ever changes, we will need to modify this test.
        XCTAssertEqual(keys.count, 3)

        // Test the last key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[2]).swift"), bytes: "// swift-tools-version:3.4.1\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.1")
        }

        // Test the second last key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[1]).swift"), bytes: "// swift-tools-version:3.4.0\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.0")
        }

        // Test the first key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[0]).swift"), bytes: "// swift-tools-version:3.4.5\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.5")
        }
    }

    func assertFailure(_ bytes: ByteString, _ theSpecifier: String, file: StaticString = #file, line: UInt = #line) {
        do {
            try load(bytes) {
                XCTFail("unexpected success - \($0)", file: file, line: line)
            }
            XCTFail("unexpected success", file: file, line: line)
        } catch ToolsVersionLoader.Error.malformed(let specifier, let path) {
            XCTAssertEqual(specifier, theSpecifier, file: file, line: line)
            XCTAssertEqual(path, AbsolutePath("/pkg/Package.swift"), file: file, line: line)
        } catch {
            XCTFail("Failed with error \(error)")
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testNonMatching", testNonMatching),
        ("testVersionSpecificManifest", testVersionSpecificManifest),
    ]
}
