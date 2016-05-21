/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Utility
import XCTest

#if os(Linux)
    import Foundation  // String.hasSuffix
#endif

class FileTests: XCTestCase {

    private func loadInputFile(_ name: String) throws -> NSFileHandle {
        let input = Path.join(#file, "../Inputs", name).normpath
        return try fopen(input, mode: .read)
    }
    
    func testOpenFile() {
        do {
            let file = try loadInputFile("empty_file")
            var generator = try file.enumerate()
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testOpenFileFail() {
        do {
            let file = try loadInputFile("file_not_existing")
            let _ = try file.enumerate()
            XCTFail("The file should not be opened since it is not existing")
        } catch {
            
        }
    }
    
    func testReadRegularTextFile() {
        do {
            let file = try loadInputFile("regular_text_file")
            var generator = try file.enumerate()
            XCTAssertEqual(generator.next(), "Hello world")
            XCTAssertEqual(generator.next(), "It is a regular text file.")
            XCTAssertEqual(generator.next(), "")
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testReadRegularTextFileWithSeparator() {
        do {
            let file = try loadInputFile("regular_text_file")
            var generator = try file.enumerate(separatedBy: " ")
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

extension FileTests {
    static var allTests : [(String, (FileTests) -> () throws -> Void)] {
        return [
                   ("testOpenFile", testOpenFile),
                   ("testOpenFileFail", testOpenFileFail),
                   ("testReadRegularTextFile", testReadRegularTextFile),
                   ("testReadRegularTextFileWithSeparator", testReadRegularTextFileWithSeparator)
        ]
    }
}
