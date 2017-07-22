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

final class BuildToolTests: XCTestCase {
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["-help"]).contains("USAGE: swift build"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testBinPath() throws {
        fixture(name: "ValidLayouts/SingleModule/Executable") { path in
            let fullPath = resolveSymlinks(path)
            let targetPath = fullPath.appending(components: ".build", Destination.host.target)
            XCTAssertEqual(try execute(["--show-bin-path"], packagePath: fullPath),
                           targetPath.appending(components: "debug").asString + "\n")
            XCTAssertEqual(try execute(["-c", "release", "--show-bin-path"], packagePath: fullPath),
                           targetPath.appending(components: "release").asString + "\n")
        }
    }

    func testBackwardsCompatibilitySymlink() throws {
        fixture(name: "ValidLayouts/SingleModule/Executable") { path in
            let fullPath = resolveSymlinks(path)
            let targetPath = fullPath.appending(components: ".build", Destination.host.target)

            _ = try execute([], packagePath: fullPath)
            XCTAssertEqual(resolveSymlinks(fullPath.appending(components: ".build", "debug")),
                           targetPath.appending(component: "debug"))

            _ = try execute(["-c", "release"], packagePath: fullPath)
            XCTAssertEqual(resolveSymlinks(fullPath.appending(components: ".build", "release")),
                           targetPath.appending(component: "release"))
        }
    }

    func testProductAndTarget() throws {
        fixture(name: "Miscellaneous/MultipleExecutables") { path in
            let productOutput = try execute(["--product", "exec1"], packagePath: path)
            XCTAssert(productOutput.contains("Compile"))
            XCTAssert(productOutput.contains("Linking"))
            XCTAssert(productOutput.contains("exec1"))
            XCTAssert(!productOutput.contains("exec2"))

            let targetOutput = try execute(["--target", "exec2"], packagePath: path)
            XCTAssert(targetOutput.contains("Compile"))
            XCTAssert(targetOutput.contains("exec2"))
            XCTAssert(!targetOutput.contains("Linking"))
            XCTAssert(!targetOutput.contains("exec1"))

            do {
                _ = try execute(["--product", "exec1", "--target", "exec2"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--product' and '--target' are mutually exclusive\n")
            }

            do {
                _ = try execute(["--product", "exec1", "--build-tests"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--product' and '--build-tests' are mutually exclusive\n")
            }

            do {
                _ = try execute(["--build-tests", "--target", "exec2"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--target' and '--build-tests' are mutually exclusive\n")
            }

            do {
                _ = try execute(["--build-tests", "--target", "exec2", "--product", "exec1"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--product', '--target', and '--build-tests' are mutually exclusive\n")
            }

            do {
                _ = try execute(["--product", "UnkownProduct"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: no product named 'UnkownProduct'\n")
            }

            do {
                _ = try execute(["--target", "UnkownTarget"], packagePath: path)
                XCTFail("Expected to fail")
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: no target named 'UnkownTarget'\n")
            }
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testBinPath", testBinPath),
        ("testBackwardsCompatibilitySymlink", testBackwardsCompatibilitySymlink),
        ("testProductAndTarget", testProductAndTarget)
    ]
}
