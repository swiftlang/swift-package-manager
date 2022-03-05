/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import SPMTestSupport
import Commands
import TSCBasic

final class RunToolTests: CommandsTestCase {
    
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil
    ) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftRun.execute(args, packagePath: packagePath)
    }

    func testUsage() throws {
        let stdout = try execute(["-help"]).stdout
        XCTAssert(stdout.contains("USAGE: swift run <options>") || stdout.contains("USAGE: swift run [<options>]"), "got stdout:\n" + stdout)
    }

    func testSeeAlso() throws {
        let stdout = try execute(["--help"]).stdout
        XCTAssert(stdout.contains("SEE ALSO: swift build, swift package, swift test"), "got stdout:\n" + stdout)
    }

    func testVersion() throws {
        let stdout = try execute(["--version"]).stdout
        XCTAssert(stdout.contains("Swift Package Manager"), "got stdout:\n" + stdout)
    }

    func testUnknownProductAndArgumentPassing() throws {
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in

            let result = try SwiftPMProduct.SwiftRun.executeProcess(
                ["secho", "1", "--hello", "world"], packagePath: fixturePath)

            // We only expect tool's output on the stdout stream.
            XCTAssertMatch(try result.utf8Output(), .contains("""
                "1" "--hello" "world"
                """))

            // swift-build-tool output should go to stderr.
            XCTAssertMatch(try result.utf8stderrOutput(), .regex("Compiling"))
            XCTAssertMatch(try result.utf8stderrOutput(), .contains("Linking"))

            XCTAssertThrowsCommandExecutionError(try execute(["unknown"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: no executable product named 'unknown'"))
            }
        }
    }

    func testMultipleExecutableAndExplicitExecutable() throws {
        try fixture(name: "Miscellaneous/MultipleExecutables") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute([], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: multiple executable products available: exec1, exec2"))
            }
            
            var (runOutput, _) = try execute(["exec1"], packagePath: fixturePath)
            XCTAssertMatch(runOutput, .contains("1"))

            (runOutput, _) = try execute(["exec2"], packagePath: fixturePath)
            XCTAssertMatch(runOutput, .contains("2"))
        }
    }

    func testUnreachableExecutable() throws {
        try fixture(name: "Miscellaneous/UnreachableTargets") { fixturePath in
            let (output, _) = try execute(["bexec"], packagePath: fixturePath.appending(component: "A"))
            let outputLines = output.split(separator: "\n")
            XCTAssertMatch(String(outputLines[0]), .contains("BTarget2"))
        }
    }

    func testFileDeprecation() throws {
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let filePath = AbsolutePath(fixturePath, "Sources/secho/main.swift").pathString
            let cwd = localFileSystem.currentWorkingDirectory!
            let (stdout, stderr) = try execute([filePath, "1", "2"], packagePath: fixturePath)
            XCTAssertMatch(stdout, .contains(#""\#(cwd)" "1" "2""#))
            XCTAssertMatch(stderr, .contains("warning: 'swift run file.swift' command to interpret swift files is deprecated; use 'swift file.swift' instead"))
        }
    }

    func testMutualExclusiveFlags() throws {
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute(["--build-tests", "--skip-build"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--build-tests' and '--skip-build' are mutually exclusive"))
            }
        }
    }
}
