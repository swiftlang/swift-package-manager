/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Commands
import SPMTestSupport
import TSCBasic
import XCTest

final class TestToolTests: CommandsTestCase {
    
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftTest.execute(args, packagePath: packagePath)
    }
    
    func testUsage() throws {
        let stdout = try execute(["-help"]).stdout
        XCTAssert(stdout.contains("USAGE: swift test"), "got stdout:\n" + stdout)
    }

    func testSeeAlso() throws {
        let stdout = try execute(["--help"]).stdout
        XCTAssert(stdout.contains("SEE ALSO: swift build, swift run, swift package"), "got stdout:\n" + stdout)
    }

    func testVersion() throws {
        let stdout = try execute(["--version"]).stdout
        XCTAssert(stdout.contains("Swift Package Manager"), "got stdout:\n" + stdout)
    }

    func testNumWorkersParallelRequirement() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute(["--num-workers", "1"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: --num-workers must be used with --parallel"))
            }
        }
    }
    
    func testNumWorkersValue() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute(["--parallel", "--num-workers", "0"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--num-workers' must be greater than zero"))
            }
        }
    }

    func testEnableDisableTestability() throws {
        // default should run with testability
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try execute(["--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }

        // disabled
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            XCTAssertThrowsCommandExecutionError( try execute(["--disable-testable-imports", "--vv"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("was not compiled for testing"))
            }
        }

        // enabled
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try execute(["--enable-testable-imports", "--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }
    }
}
