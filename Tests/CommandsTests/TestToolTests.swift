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

    func testSanitizeScudo() throws {
        // This test only runs on Linux because Scudo only runs on Linux
      #if os(Linux)
        fixture(name: "Miscellaneous/DoubleFree") { path in
            let cmdline = {
                try SwiftPMProduct.SwiftTest.execute(
                    ["--sanitize=scudo"], packagePath: path)
            }
            XCTAssertThrows(try cmdline()) { (error: SwiftPMProductError) in
                switch error {
                case .executionFailure(_, _, let error):
                    XCTAssertMatch(error, .contains("invalid chunk state"))
                    return true
                default:
                    return false
                }
            }
        }
      #endif
    }
}
