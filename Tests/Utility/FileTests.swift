/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Utility
import XCTest

class FileTests: XCTestCase {

    private func loadInputFile(name: String) -> File {
        let input = Path.join(#file, "../Inputs", name).normpath
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


#if os(Linux)
extension FileTests:  XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testOpenFile", testOpenFile),
            ("testOpenFileFail", testOpenFileFail),
            ("testReadRegularTextFile", testReadRegularTextFile),
            ("testReadRegularTextFileWithSeparator", testReadRegularTextFileWithSeparator)
        ]
    }
}


extension RmtreeTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testDoesNotFollowSymlinks", testDoesNotFollowSymlinks),
        ]
    }
}

extension PathTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("test", test),
            ("testPrecombined", testPrecombined),
            ("testExtraSeparators", testExtraSeparators),
            ("testEmpties", testEmpties),
            ("testNormalizePath", testNormalizePath),
            ("testJoinWithAbsoluteReturnsLastAbsoluteComponent", testJoinWithAbsoluteReturnsLastAbsoluteComponent),
            ("testParentDirectory", testParentDirectory),
        ]
    }
}

extension WalkTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testNonRecursive", testNonRecursive),
            ("testRecursive", testRecursive),
            ("testSymlinksNotWalked", testSymlinksNotWalked),
            ("testWalkingADirectorySymlinkResolvesOnce", testWalkingADirectorySymlinkResolvesOnce),
        ]
    }
}

extension StatTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("test_isdir", test_isdir),
            ("test_isfile", test_isfile),
            ("test_realpath", test_realpath),
            ("test_basename", test_basename),
        ]
    }
}

extension RelativePathTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testAbsolute", testAbsolute),
            ("testRelative", testRelative),
            ("testMixed", testMixed),
        ]
    }
}


extension ResourcesTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testResources", testResources),
        ]
    }
}

extension ShellTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testPopen", testPopen),
            ("testPopenWithBufferLargerThanThatAllocated", testPopenWithBufferLargerThanThatAllocated),
            ("testPopenWithBinaryOutput", testPopenWithBinaryOutput)
        ]
    }
}


extension StringTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testTrailingChomp", testTrailingChomp),
            ("testEmptyChomp", testEmptyChomp),
            ("testSeparatorChomp", testSeparatorChomp),
            ("testChuzzle", testChuzzle),
        ]
    }
    
}

extension URLTests: XCTestCaseProvider {
    var allTests : [(String, () throws -> Void)] {
        return [
            ("testSchema", testSchema),
        ]
    }
}
#endif
