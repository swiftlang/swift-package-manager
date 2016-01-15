/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import XCTestCaseProvider
@testable import sys

class FileTests: XCTestCase,  XCTestCaseProvider {

    var allTests : [(String, () throws -> Void)] {
        return [
            ("testOpenFile", testOpenFile),
            ("testOpenFileFail", testOpenFileFail),
            ("testReadRegularTextFile", testReadRegularTextFile),
            ("testReadRegularTextFileWithSeparator", testReadRegularTextFileWithSeparator)
        ]
    }
    
    private func loadInputFile(name: String) -> File {
        let input = Path.join(__FILE__, "../Inputs", name).normpath
        return File(path: input)
    }
    
    func testOpenFile() {
        let file = loadInputFile("empty_file")
        do {
            let generator = try file.enumerate()
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testOpenFileFail() {
        let file = loadInputFile("file_not_existing")
        do {
            let _ = try file.enumerate()
            XCTFail("The file should not be opened since it is not existing")
        } catch {
            
        }
    }
    
    func testReadRegularTextFile() {
        let file = loadInputFile("regular_text_file")
        do {
            let generator = try file.enumerate()
            XCTAssertEqual(generator.next(), "Hello world")
            XCTAssertEqual(generator.next(), "It is a regular text file.")
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testReadRegularTextFileWithSeparator() {
        let file = loadInputFile("regular_text_file")
        do {
            let generator = try file.enumerate(" ")
            XCTAssertEqual(generator.next(), "Hello")
            XCTAssertEqual(generator.next(), "world\nIt")
            XCTAssertEqual(generator.next(), "is")
            XCTAssertEqual(generator.next(), "a")
            XCTAssertEqual(generator.next(), "regular")
            XCTAssertEqual(generator.next(), "text")
            XCTAssertEqual(generator.next(), "file.\n")
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
}
