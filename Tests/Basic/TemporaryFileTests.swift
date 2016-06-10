/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utility
import Basic

class TemporaryFileTests: XCTestCase {
    func testBasicReadWrite() throws {
        let filePath: String
        do {
            let file = try TemporaryFile(prefix: "myprefix", suffix: "mysuffix")
            // Make sure the filename contains our prefix and suffix.
            XCTAssertTrue(file.path.basename.hasPrefix("myprefix"))
            XCTAssertTrue(file.path.basename.hasSuffix("mysuffix"))

            // Check if file is created.
            XCTAssertTrue(file.path.isFile)

            // Try writing some data to the file.
            let stream = OutputByteStream()
            stream <<< "foo"
            stream <<< "bar"
            stream <<< "baz"
            try fputs(stream.bytes.contents, file.fileHandle)

            // Go to the begining of the file.
            file.fileHandle.seek(toFileOffset: 0)
            // Read the contents.
            let contents = try? file.fileHandle.readFileContents()
            XCTAssertEqual(contents, "foobarbaz")

            filePath = file.path
        }
        // File should be deleted now.
        XCTAssertFalse(filePath.isFile)
    }

    func testCanCreateUniqueTempFiles() throws {
        let filePathOne: String
        let filePathTwo: String
        do {
            let fileOne = try TemporaryFile()
            let fileTwo = try TemporaryFile()
            // Check files exists.
            XCTAssertTrue(fileOne.path.isFile)
            XCTAssertTrue(fileTwo.path.isFile)
            // Their paths should be different.
            XCTAssertTrue(fileOne.path != fileTwo.path)

            filePathOne = fileOne.path
            filePathTwo = fileTwo.path
        }
        XCTAssertFalse(filePathOne.isFile)
        XCTAssertFalse(filePathTwo.isFile)
    }

    static var allTests = [
        ("testBasicReadWrite", testBasicReadWrite),
        ("testCanCreateUniqueTempFiles", testCanCreateUniqueTempFiles),
    ]
}
