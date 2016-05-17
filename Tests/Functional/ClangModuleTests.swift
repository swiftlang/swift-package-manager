/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import struct Utility.Path
import func POSIX.symlink
import func Utility.walk
import func POSIX.rename
import func POSIX.mkdir
import func POSIX.popen

class ClangModulesTestCase: XCTestCase {
    func testSingleModuleFlatCLibrary() {
        fixture(name: "ClangModules/CLibraryFlat") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "libCLibraryFlat.so")
        }
    }
    
    func testSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "libCLibrarySources.so")
        }
    }
    
    func testMixedSwiftAndC() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "libSeaLib.so")
            let exec = ".build/debug/SeaExec"
            XCTAssertFileExists(prefix, exec)
            let output = try popen([Path.join(prefix, exec)])
            XCTAssertEqual(output, "a = 5\n")
        }
    }
    
    func testExternalSimpleCDep() {
        fixture(name: "DependencyResolution/External/SimpleCDep") { prefix in
            XCTAssertBuilds(prefix, "Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/libFoo.so")
            XCTAssertDirectoryExists(prefix, "Bar/Packages/Foo-1.2.3")
        }
    }
    
    func testiquoteDep() {
        fixture(name: "ClangModules/CLibraryiquote") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "libFoo.so")
            XCTAssertFileExists(prefix, ".build", "debug", "libBar.so")
        }
    }
    
    func testCUsingCDep() {
        fixture(name: "DependencyResolution/External/CUsingCDep") { prefix in
            XCTAssertBuilds(prefix, "Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/libFoo.so")
            XCTAssertDirectoryExists(prefix, "Bar/Packages/Foo-1.2.3")
        }
    }
    
    func testCExecutable() {
        fixture(name: "ValidLayouts/SingleModule/CExecutable") { prefix in
            XCTAssertBuilds(prefix)
            let exec = ".build/debug/CExecutable"
            XCTAssertFileExists(prefix, exec)
            let output = try popen([Path.join(prefix, exec)])
            XCTAssertEqual(output, "hello 5")
        }
    }
    
    func testCUsingCDep2() {
        //The C dependency "Foo" has different layout
        fixture(name: "DependencyResolution/External/CUsingCDep2") { prefix in
            XCTAssertBuilds(prefix, "Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/libFoo.so")
            XCTAssertDirectoryExists(prefix, "Bar/Packages/Foo-1.2.3")
        }
    }
    
    func testModuleMapGenerationCases() {
        fixture(name: "ClangModules/ModuleMapGenerationCases") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix, ".build", "debug", "libUmbrellaHeader.so")
            XCTAssertFileExists(prefix, ".build", "debug", "libFlatInclude.so")
            XCTAssertFileExists(prefix, ".build", "debug", "libUmbellaModuleNameInclude.so")
            XCTAssertFileExists(prefix, ".build", "debug", "libNoIncludeDir.so")
            XCTAssertFileExists(prefix, ".build", "debug", "Baz")
        }
    }

    func testCanForwardExtraFlagsToClang() {
        // Try building a fixture which needs extra flags to be able to build.
        fixture(name: "ClangModules/CDynamicLookup") { prefix in
            XCTAssertBuilds(prefix, Xld: ["-undefined", "dynamic_lookup"])
            XCTAssertFileExists(prefix, ".build", "debug", "libCDynamicLookup.so")
        }
    }
}


extension ClangModulesTestCase {
    static var allTests : [(String, (ClangModulesTestCase) -> () throws -> Void)] {
        return [
            ("testSingleModuleFlatCLibrary", testSingleModuleFlatCLibrary),
            ("testSingleModuleCLibraryInSources", testSingleModuleCLibraryInSources),
            ("testMixedSwiftAndC", testMixedSwiftAndC),
            ("testExternalSimpleCDep", testExternalSimpleCDep),
            ("testiquoteDep", testiquoteDep),
            ("testCUsingCDep", testCUsingCDep),
            ("testCExecutable", testCExecutable),
            ("testModuleMapGenerationCases", testModuleMapGenerationCases),
            ("testCanForwardExtraFlagsToClang", testCanForwardExtraFlagsToClang),
        ]
    }
}
