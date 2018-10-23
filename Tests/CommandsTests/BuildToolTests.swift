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
import Workspace

struct BuildResult {
    let output: String
    let binContents: [String]
}

final class BuildToolTests: XCTestCase {
    @discardableResult
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftBuild.execute(args, packagePath: packagePath)
    }

    func build(_ args: [String], packagePath: AbsolutePath? = nil) throws -> BuildResult {
        let output = try execute(args, packagePath: packagePath)
        defer { try! SwiftPMProduct.SwiftPackage.execute(["clean"], packagePath: packagePath) }
        let binPathOutput = try execute(["--show-bin-path"], packagePath: packagePath)
        let binPath = AbsolutePath(binPathOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        let binContents = try localFileSystem.getDirectoryContents(binPath)
        return BuildResult(output: output, binContents: binContents)
    }

    func testUsage() throws {
        XCTAssert(try execute(["-help"]).contains("USAGE: swift build"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).contains("SEE ALSO: swift run, swift package, swift test"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testBinPathAndSymlink() throws {
        fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { path in
            let fullPath = resolveSymlinks(path)
            let targetPath = fullPath.appending(components: ".build", Destination.host.target)
            XCTAssertEqual(try execute(["--show-bin-path"], packagePath: fullPath),
                           targetPath.appending(components: "debug").asString + "\n")
            XCTAssertEqual(try execute(["-c", "release", "--show-bin-path"], packagePath: fullPath),
                           targetPath.appending(components: "release").asString + "\n")

            // Test symlink.
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
            let fullPath = resolveSymlinks(path)

            do {
                let result = try build(["--product", "exec1"], packagePath: fullPath)
                XCTAssert(result.binContents.contains("exec1"))
                XCTAssert(!result.binContents.contains("exec2.build"))
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }

            do {
                let output = try execute(["--product", "lib1"], packagePath: fullPath)
                try SwiftPMProduct.SwiftPackage.execute(["clean"], packagePath: fullPath)
                XCTAssertTrue(output.contains("'--product' cannot be used with the automatic product 'lib1'. Building the default target instead"), output)
            }

            do {
                let result = try build(["--target", "exec2"], packagePath: fullPath)
                XCTAssert(result.binContents.contains("exec2.build"))
                XCTAssert(!result.binContents.contains("exec1"))
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }

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

    func testNonReachableProductsAndTargetsFunctional() {
        fixture(name: "Miscellaneous/UnreachableTargets") { path in
            let aPath = path.appending(component: "A")

            do {
                let result = try build([], packagePath: aPath)
                XCTAssert(!result.binContents.contains("bexec"))
                XCTAssert(!result.binContents.contains("BTarget2.build"))
                XCTAssert(!result.binContents.contains("cexec"))
                XCTAssert(!result.binContents.contains("CTarget.build"))
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }

            // Dependency contains a dependent product

            do {
                let result = try build(["--product", "bexec"], packagePath: aPath)
                XCTAssert(result.binContents.contains("BTarget2.build"))
                XCTAssert(result.binContents.contains("bexec"))
                XCTAssert(!result.binContents.contains("aexec"))
                XCTAssert(!result.binContents.contains("ATarget.build"))
                XCTAssert(!result.binContents.contains("BLibrary.a"))
                XCTAssert(!result.binContents.contains("BTarget1.build"))
                XCTAssert(!result.binContents.contains("cexec"))
                XCTAssert(!result.binContents.contains("CTarget.build"))
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }

            // Dependency does not contain a dependent product

            do {
                let result = try build(["--target", "CTarget"], packagePath: aPath)
                XCTAssert(result.binContents.contains("CTarget.build"))
                XCTAssert(!result.binContents.contains("aexec"))
                XCTAssert(!result.binContents.contains("ATarget.build"))
                XCTAssert(!result.binContents.contains("BLibrary.a"))
                XCTAssert(!result.binContents.contains("bexec"))
                XCTAssert(!result.binContents.contains("BTarget1.build"))
                XCTAssert(!result.binContents.contains("BTarget2.build"))
                XCTAssert(!result.binContents.contains("cexec"))
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTFail(stderr)
            }
        }
    }
}
