//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Commands
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

typealias Process = TSCBasic.Process

/// Asserts if a directory (recursively) contains a file.
private func XCTAssertDirectoryContainsFile(dir: AbsolutePath, filename: String, file: StaticString = #file, line: UInt = #line) {
    do {
        for entry in try walk(dir) {
            if entry.basename == filename { return }
        }
    } catch {
        XCTFail("Failed with error \(error)", file: file, line: line)
    }
    XCTFail("Directory \(dir) does not contain \(file)", file: file, line: line)
}

class CFamilyTargetTestCase: XCTestCase {

    func testCLibraryWithSpaces() throws {
        try fixture(name: "CFamilyTargets/CLibraryWithSpaces") { fixturePath in
            XCTAssertBuilds(fixturePath)
            let debugPath = fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Bar.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }

    func testCUsingCAndSwiftDep() throws {
        try fixture(name: "DependencyResolution/External/CUsingCDep") { fixturePath in
            let packageRoot = fixturePath.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = fixturePath.appending(components: "Bar", ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Sea.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(try GitRepository(path: path).getTags(), ["1.2.3"])
        }
    }

    func testModuleMapGenerationCases() throws {
        try fixture(name: "CFamilyTargets/ModuleMapGenerationCases") { fixturePath in
            XCTAssertBuilds(fixturePath)
            let debugPath = fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Jaz.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "main.swift.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "FlatInclude.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "UmbrellaHeader.c.o")
        }
    }
    
    func testNoIncludeDirCheck() throws {
        try fixture(name: "CFamilyTargets/CLibraryNoIncludeDir") { fixturePath in
            XCTAssertThrowsError(try executeSwiftBuild(fixturePath), "This build should throw an error") { err in
                // The err.localizedDescription doesn't capture the detailed error string so interpolate
                let errStr = "\(err)"
                let missingIncludeDirStr = "\(ModuleError.invalidPublicHeadersDirectory("Cfactorial"))"
                XCTAssert(errStr.contains(missingIncludeDirStr))
            }
        }
    }

    func testCanForwardExtraFlagsToClang() throws {
        // Try building a fixture which needs extra flags to be able to build.
        try fixture(name: "CFamilyTargets/CDynamicLookup") { fixturePath in
            XCTAssertBuilds(fixturePath, Xld: ["-undefined", "dynamic_lookup"])
            let debugPath = fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }

    func testObjectiveCPackageWithTestTarget() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "CFamilyTargets/ObjCmacOSPackage") { fixturePath in
            // Build the package.
            XCTAssertBuilds(fixturePath)
            XCTAssertDirectoryContainsFile(dir: fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug"), filename: "HelloWorldExample.m.o")
            // Run swift-test on package.
            XCTAssertSwiftTest(fixturePath)
        }
    }
    
    func testCanBuildRelativeHeaderSearchPaths() throws {
        try fixture(name: "CFamilyTargets/CLibraryParentSearchPath") { fixturePath in
            XCTAssertBuilds(fixturePath)
            XCTAssertDirectoryContainsFile(dir: fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug"), filename: "HeaderInclude.swiftmodule")
        }
    }
}
