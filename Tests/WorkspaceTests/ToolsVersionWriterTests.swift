/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
import Workspace

class ToolsVersionWriterTests: XCTestCase {

    func testBasics() throws {
        // Empty file.
        var stream = BufferedOutputByteStream()
        stream <<< ""

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n")
        }

        // File with just a new line.
        stream = BufferedOutputByteStream()
        stream <<< "\n"

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n\n")
        }

        // File with some contents.
        stream = BufferedOutputByteStream()
        stream <<< "let package = ... " <<< "\n"

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\nlet package = ... \n")
        }

        // File already having a valid version.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:3.1.2\n"
        stream <<< "..."

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Write a version with zero in patch number.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:3.1.2\n"
        stream <<< "..."

        writeToolsVersionCover(stream, version: ToolsVersion(version: "2.1.0")) { result in
            XCTAssertEqual(result, "// swift-tools-version:2.1\n...")
        }

        // Contents with invalid specifier line.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tool-version:3.1.2\n"
        stream <<< "..."

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n// swift-tool-version:3.1.2\n...")
        }

        // Contents with invalid specifier string.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:-3.1.2\n"
        stream <<< "..."

        writeToolsVersionCover(stream) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Contents with valid specifier string and some meta data.
        stream = BufferedOutputByteStream()
        stream <<< "// swift-tools-version:-3.1.2;hello\n"
        stream <<< "..."

        writeToolsVersionCover(stream) { result in
            // Note: Right now we lose the metadata but if we ever start using it, we should preserve it.
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }

        // Try to write a version with prerelease and build meta data.
        let toolsVersion = ToolsVersion(version: "4.1.2-alpha.beta+sha.1234")
        writeToolsVersionCover(stream, version: toolsVersion) { result in
            XCTAssertEqual(result, "// swift-tools-version:4.1.2\n...")
        }
    }

    func testZeroedPatchVersion() {
        XCTAssertEqual(ToolsVersion(version: "4.2.1").zeroedPatch.description, "4.2.0")
        XCTAssertEqual(ToolsVersion(version: "4.2.0").zeroedPatch.description, "4.2.0")
        XCTAssertEqual(ToolsVersion(version: "6.0.129").zeroedPatch.description, "6.0.0")
    }

    func writeToolsVersionCover(
        _ stream: BufferedOutputByteStream,
        version: ToolsVersion = ToolsVersion(version: "4.1.2"),
        _ result: (ByteString) -> Void
    ) {
        do {
            var fs: FileSystem = InMemoryFileSystem()

            let file = AbsolutePath("/pkg/Package.swift")

            try fs.createDirectory(file.parentDirectory, recursive: true)
            try fs.writeFileContents(file, bytes: stream.bytes)

            try writeToolsVersion(
                at: file.parentDirectory, version: version, fs: &fs)

            result(try fs.readFileContents(file))
        } catch {
            XCTFail("Failed with error \(error)")
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testZeroedPatchVersion", testZeroedPatchVersion),
    ]
}
