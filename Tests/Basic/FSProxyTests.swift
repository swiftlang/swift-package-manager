/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

func XCTAssertThrows<T where T: ErrorProtocol, T: Equatable>(_ expectedError: T, file: StaticString = #file, line: UInt = #line, _ body: () throws -> ()) {
    do {
        try body()
        XCTFail("body completed successfully", file: file, line: line)
    } catch let error as T {
        XCTAssertEqual(error, expectedError)
    } catch {
        XCTFail("unexpected error thrown", file: file, line: line)
    }
}

class FSProxyTests: XCTestCase {

    // MARK: LocalFS Tests

    // FIXME: Implement
    
    // MARK: PseudoFS Tests

    func testPseudoBasics() {
        let fs = PseudoFS()

        // exists()
        XCTAssert(!fs.exists("/does-not-exist"))

        // isDirectory()
        XCTAssert(!fs.isDirectory("/does-not-exist"))

        // createDirectory()
        XCTAssertThrows(FSProxyError.noEntry) {
            _ = try fs.getDirectoryContents("/does-not-exist")
        }
    }
    
    static var allTests = [
        ("testPseudoBasics", testPseudoBasics),
    ]
}
