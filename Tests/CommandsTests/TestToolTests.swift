/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
import Commands

final class TestToolTests: XCTestCase {
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil, printIfError: Bool = true) throws -> String {
        return try SwiftPMProduct.SwiftTest.execute(args, packagePath: packagePath, printIfError: printIfError)
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

    // Verifies that sanitization works
    func testSanitizeThread() throws {
        #if os(macOS)
        fixture(name: "Miscellaneous/SanitizersTest") { path in
            let cmdline = ["--sanitize=thread"]
            XCTAssertThrows(try execute(cmdline, packagePath: path, printIfError: false)) { (error: SwiftPMProductError) -> Bool in
                switch error {
                case .executionFailure(_, _, let stderr):
                    return stderr.range(of: "ThreadSanitizer:") != nil
                        && stderr.range(of: "access race") != nil
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
