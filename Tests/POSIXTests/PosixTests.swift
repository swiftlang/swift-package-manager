/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

@testable import POSIX

import Basic
import TestSupport

class PosixTests: XCTestCase {

    var fs = localFileSystem

    func testRename() throws {

        mktmpdir { path in
            let foo = path.appending(component: "foo.swift")
            let bar = path.appending(component: "bar.swift")
            try fs.writeFileContents(foo) { _ in }
            XCTAssertTrue(fs.isFile(foo))

            try rename(old: foo.asString, new: bar.asString)
            XCTAssertFalse(fs.isFile(foo))
            XCTAssertTrue(fs.isFile(bar))

            do {
                try rename(old: foo.asString, new: bar.asString)
                XCTFail()
            } catch SystemError.rename {}
        }
    }

    func testExecutableRealpath() throws {
        var path = ""
        XCTAssertNoThrow(path = try realpath(executable: CommandLine.arguments.first!))
        XCTAssertTrue(path.hasPrefix(pathComponentSeparator))

        XCTAssertNoThrow(path = try realpath(executable: "swift"))
        XCTAssertEqual(path, "/usr/bin/swift")

        XCTAssertThrowsError(try realpath(executable: "a-definitely-not-exist-executable"))
    }

    static var allTests = [
        ("testRename", testRename),
        ("testExecutableRealpath", testExecutableRealpath),
    ]
}
