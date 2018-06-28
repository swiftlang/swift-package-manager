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
import Basic
import POSIX

final class RunToolTests: XCTestCase {
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftRun.execute(args, packagePath: packagePath, printIfError: true)
    }

    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift run [options] [executable [arguments ...]]"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).contains("SEE ALSO: swift build, swift package, swift test"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
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
            XCTAssertMatch(try result.utf8stderrOutput(), .contains("Compile Swift Module"))
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
            
            var runOutput = try execute(["exec1"], packagePath: path)
            XCTAssertMatch(runOutput, .contains("1"))

            runOutput = try execute(["exec2"], packagePath: path)
            XCTAssertMatch(runOutput, .contains("2"))
        }
    }

    func testUnreachableExecutable() throws {
        fixture(name: "Miscellaneous/UnreachableTargets") { path in
            let output = try execute(["bexec"], packagePath: path.appending(component: "A"))
            let outputLines = output.split(separator: "\n")
            XCTAssertEqual(outputLines.first, "BTarget2")
        }
    }

    func testFileDeprecation() throws {
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            let filePath = AbsolutePath(path, "Sources/secho/main.swift").asString
            XCTAssertEqual(try execute([filePath, "1", "2"], packagePath: path), """
                "\(getcwd())" "1" "2"
                warning: 'swift run file.swift' command to interpret swift files is deprecated; use 'swift file.swift' instead
                
                """)
        }
    }

    // Test that thread sanitizer works.
    func testSanitizeThread() throws {
        // FIXME: We need to figure out how to test this for linux.
      #if os(macOS)
        fixture(name: "Miscellaneous/ThreadRace") { path in
            // Ensure that we don't abort() when we find the race. This avoids
            // generating the crash report on macOS.
            let env = ["TSAN_OPTIONS": "abort_on_error=0"]
            let cmdline = {
                try SwiftPMProduct.SwiftRun.execute(
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
        ("testUnkownProductAndArgumentPassing", testUnkownProductAndArgumentPassing),
        ("testMultipleExecutableAndExplicitExecutable", testMultipleExecutableAndExplicitExecutable),
        ("testUnreachableExecutable", testUnreachableExecutable),
        ("testFileDeprecation", testFileDeprecation),
        ("testSanitizeThread", testSanitizeThread),
    ]
}
