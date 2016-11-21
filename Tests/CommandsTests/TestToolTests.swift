/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
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
#if os(macOS)
        XCTAssert(try execute(["--help"]).contains("USAGE: swift test"))
#endif
    }

    func testVersion() throws {
#if os(macOS)
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
#endif
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
    ]
}
