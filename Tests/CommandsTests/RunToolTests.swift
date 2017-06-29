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

final class RunToolTests: XCTestCase {
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftRun.execute(args, packagePath: packagePath, printIfError: true)
    }

    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift run [options] [executable [arguments ...]]"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testFunctional() throws {
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["unknown"], packagePath: path)
                XCTFail("Unexpected success")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: could not find executable product 'unknown' in the package\n")
            }

            let runOutput = try execute(["secho", "1", "--hello", "world"], packagePath: path)
            let outputLines = runOutput.split(separator: "\n")
            XCTAssertEqual(outputLines.last!, "\"1\" \"--hello\" \"world\"")
        }

        fixture(name: "Miscellaneous/MultipleExecutables") { path in
            do {
                _ = try execute([], packagePath: path)
                XCTFail("Unexpected success")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: multiple executable products in the package. Use `swift run ` followed by one of: exec1, exec2\n")
            }
            
            var runOutput = try execute(["exec1"], packagePath: path)
            var outputLines = runOutput.split(separator: "\n")
            XCTAssertEqual(outputLines.last!, "1")
            runOutput = try execute(["exec2"], packagePath: path)
            outputLines = runOutput.split(separator: "\n")
            XCTAssertEqual(outputLines.last!, "2")
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testFunctional", testFunctional)
    ]
}
