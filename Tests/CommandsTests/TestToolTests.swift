/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import SPMTestSupport
import Commands

final class TestToolTests: XCTestCase {
    private func execute(_ args: [String]) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftTest.execute(args)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("USAGE: swift test"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("SEE ALSO: swift build, swift run, swift package"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).stdout.contains("Swift Package Manager"))
    }

    func testNumWorkersParallelRequeriment() throws {
        // Running swift-test fixtures on linux is not yet possible.
        #if os(macOS)
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["--num-workers", "1"])
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: --num-workers must be used with --parallel\n")
            }
        }
        #endif
    }
    
    func testNumWorkersValue() throws {
        #if os(macOS)
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["--parallel", "--num-workers", "0"])
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--num-workers' must be greater than zero\n")
            }
        }
        #endif
    }
}
