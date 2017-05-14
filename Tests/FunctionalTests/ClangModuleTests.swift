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

class ClangModulesTestCase: XCTestCase {
    func testSingleModuleFlatCLibrary() {
        fixture(name: "ClangModules/CLibraryFlat") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testMixedSwiftAndC() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "SeaExec"))
            var output = try Process.checkNonZeroExit(args: debugPath.appending(component: "SeaExec").asString)
            XCTAssertEqual(output, "a = 5\n")
            output = try Process.checkNonZeroExit(args: debugPath.appending(component: "CExec").asString)
            XCTAssertEqual(output, "5")
        }

        // This has legacy style headers and the swift target imports clang target.
        // This also has a user provided modulemap i.e. package manager will not generate it.
        fixture(name: "ClangModules/SwiftCMixed2") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            let output = try Process.checkNonZeroExit(args: debugPath.appending(component: "SeaExec").asString)
            XCTAssertEqual(output, "a = 5\n")
        }
    }
    
    func testExternalSimpleCDep() {
        fixture(name: "DependencyResolution/External/SimpleCDep") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "Bar"))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testiquoteDep() {
        fixture(name: "ClangModules/CLibraryiquote") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Bar.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testCUsingCDep() {
        fixture(name: "DependencyResolution/External/CUsingCDep") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Sea.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testCExecutable() {
        fixture(name: "ValidLayouts/SingleModule/CExecutable") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "CExecutable"))
            let output = try Process.checkNonZeroExit(args: debugPath.appending(component: "CExecutable").asString)
            XCTAssertEqual(output, "hello 5")
        }
    }
    
    func testCUsingCDep2() {
        //The C dependency "Foo" has different layout
        fixture(name: "DependencyResolution/External/CUsingCDep2") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Sea.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testModuleMapGenerationCases() {
        fixture(name: "ClangModules/ModuleMapGenerationCases") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Jaz.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "main.swift.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "FlatInclude.c.o")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "UmbrellaHeader.c.o")
        }
    }

    func testCanForwardExtraFlagsToClang() {
        // Try building a fixture which needs extra flags to be able to build.
        fixture(name: "ClangModules/CDynamicLookup") { prefix in
            XCTAssertBuilds(prefix, Xld: ["-undefined", "dynamic_lookup"])
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
        }
    }
    
    func testObjectiveCPackageWithTestTarget(){
      #if os(macOS)
        fixture(name: "ClangModules/ObjCmacOSPackage") { prefix in
            // Build the package.
            XCTAssertBuilds(prefix)
            XCTAssertDirectoryContainsFile(dir: prefix.appending(components: ".build", "debug"), filename: "HelloWorldExample.m.o")
            // Run swift-test on package.
            XCTAssertSwiftTest(prefix)
        }
      #endif
    }

    static var allTests = [
        ("testSingleModuleFlatCLibrary", testSingleModuleFlatCLibrary),
        ("testSingleModuleCLibraryInSources", testSingleModuleCLibraryInSources),
        ("testMixedSwiftAndC", testMixedSwiftAndC),
        ("testExternalSimpleCDep", testExternalSimpleCDep),
        ("testiquoteDep", testiquoteDep),
        ("testCUsingCDep", testCUsingCDep),
        ("testCUsingCDep2", testCUsingCDep2),
        ("testCExecutable", testCExecutable),
        ("testModuleMapGenerationCases", testModuleMapGenerationCases),
        ("testCanForwardExtraFlagsToClang", testCanForwardExtraFlagsToClang),
        ("testObjectiveCPackageWithTestTarget", testObjectiveCPackageWithTestTarget),
    ]
}
