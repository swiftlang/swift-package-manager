/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Commands
import TestSupport
import Basic
import PackageModel
import SourceControl
import Utility

typealias Process = Basic.Process

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

    func testiquoteDep() {
        fixture(name: "CFamilyTargets/CLibraryiquote") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Bar.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testCUsingCAndSwiftDep() {
        fixture(name: "DependencyResolution/External/CUsingCDep") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", Destination.host.target, "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Sea.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testModuleMapGenerationCases() {
        fixture(name: "CFamilyTargets/ModuleMapGenerationCases") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Jaz.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "main.swift.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "FlatInclude.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "UmbrellaHeader.c.o")
        }
    }

    func testCanForwardExtraFlagsToClang() {
        // Try building a fixture which needs extra flags to be able to build.
        fixture(name: "CFamilyTargets/CDynamicLookup") { prefix in
            XCTAssertBuilds(prefix, Xld: ["-undefined", "dynamic_lookup"])
            let debugPath = prefix.appending(components: ".build", Destination.host.target, "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testObjectiveCPackageWithTestTarget(){
      #if os(macOS)
        fixture(name: "CFamilyTargets/ObjCmacOSPackage") { prefix in
            // Build the package.
            XCTAssertBuilds(prefix)
            XCTAssertDirectoryContainsFile(dir: prefix.appending(components: ".build", Destination.host.target, "debug"), filename: "HelloWorldExample.m.o")
            // Run swift-test on package.
            XCTAssertSwiftTest(prefix)
        }
      #endif
    }

    static var allTests = [
        ("testiquoteDep", testiquoteDep),
        ("testCUsingCAndSwiftDep", testCUsingCAndSwiftDep),
        ("testModuleMapGenerationCases", testModuleMapGenerationCases),
        ("testCanForwardExtraFlagsToClang", testCanForwardExtraFlagsToClang),
        ("testObjectiveCPackageWithTestTarget", testObjectiveCPackageWithTestTarget),
    ]
}
