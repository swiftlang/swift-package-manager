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
import TSCBasic

final class RunToolTests: XCTestCase {
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil
    ) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftRun.execute(args, packagePath: packagePath)
    }

    func testUsage() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("USAGE: swift run <options>"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("SEE ALSO: swift build, swift package, swift test"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).stdout.contains("Swift Package Manager"))
    }

    func testUnkownProductAndArgumentPassing() throws {
        fixture(name: "Miscellaneous/EchoExecutable") { path in

            let result = try SwiftPMProduct.SwiftRun.executeProcess(
                ["secho", "1", "--hello", "world"], packagePath: path)

            // We only expect tool's output on the stdout stream.
            XCTAssertMatch(try result.utf8Output(), .contains("""
                "1" "--hello" "world"
                """))

            // swift-build-tool output should go to stderr.
            XCTAssertMatch(try result.utf8stderrOutput(), .regex("Compiling"))
            XCTAssertMatch(try result.utf8stderrOutput(), .contains("Linking"))

            do {
                _ = try execute(["unknown"], packagePath: path)
                XCTFail("Unexpected success")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: no executable product named 'unknown'\n")
            }
        }
    }

    func testMultipleExecutableAndExplicitExecutable() throws {
        fixture(name: "Miscellaneous/MultipleExecutables") { path in
            do {
                _ = try execute([], packagePath: path)
                XCTFail("Unexpected success")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: multiple executable products available: exec1, exec2\n")
            }
            
            var (runOutput, _) = try execute(["exec1"], packagePath: path)
            XCTAssertMatch(runOutput, .contains("1"))

            (runOutput, _) = try execute(["exec2"], packagePath: path)
            XCTAssertMatch(runOutput, .contains("2"))
        }
    }

    func testUnreachableExecutable() throws {
        fixture(name: "Miscellaneous/UnreachableTargets") { path in
            let (output, _) = try execute(["bexec"], packagePath: path.appending(component: "A"))
            let outputLines = output.split(separator: "\n")
            XCTAssertMatch(String(outputLines[0]), .contains("BTarget2"))
        }
    }

    func testFileDeprecation() throws {
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            let filePath = AbsolutePath(path, "Sources/secho/main.swift").pathString
            let cwd = localFileSystem.currentWorkingDirectory!
            let (stdout, stderr) = try execute([filePath, "1", "2"], packagePath: path)
            XCTAssertMatch(stdout, .contains(#""\#(cwd)" "1" "2""#))
            XCTAssertMatch(stderr, .contains("warning: 'swift run file.swift' command to interpret swift files is deprecated; use 'swift file.swift' instead"))
        }
    }

    func testMutualExclusiveFlags() throws {
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["--build-tests", "--skip-build"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--build-tests' and '--skip-build' are mutually exclusive\n")
            }
        }
    }
}
