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

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).contains("SEE ALSO: swift build, swift run, swift package"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    // Test that thread sanitizer works.
    func testSanitizeThread() throws {
        // FIXME: We need to figure out how to test this for linux.
        // Disabled because of https://bugs.swift.org/browse/SR-7272
      #if false
        fixture(name: "Miscellaneous/ThreadRace") { path in
            // Ensure that we don't abort() when we find the race. This avoids
            // generating the crash report on macOS.
            let env = ["TSAN_OPTIONS": "abort_on_error=0"]
            let cmdline = {
                try SwiftPMProduct.SwiftTest.execute(
                    ["--sanitize=thread"], packagePath: path, env: env)
            }
            XCTAssertThrows(try cmdline()) { (error: SwiftPMProductError) in
                switch error {
                case .executionFailure(_, _, let error):
                    XCTAssertMatch(error, .contains("ThreadSanitizer: data race"))
                    return true
                default:
                    return false
                }
            }
        }
      #endif
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testSanitizeThread", testSanitizeThread),
    ]
}
