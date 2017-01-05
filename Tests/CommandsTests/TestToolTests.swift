/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Commands

final class TestToolTests: XCTestCase {
    private func execute(_ args: [String]) throws -> String {
        return try SwiftPMProduct.SwiftTest.execute(args, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift test"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
    ]
}
