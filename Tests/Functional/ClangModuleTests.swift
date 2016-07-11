/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
import Utility

extension String {
    // FIXME: It doesn't seem right for this to be an extension on String; it isn't inherent "string behavior".
    private var soname: String {
        return "lib\(self).\(Product.dynamicLibraryExtension)"
    }
}

class ClangModulesTestCase: XCTestCase {
    func testSingleModuleFlatCLibrary() {
        fixture(name: "ClangModules/CLibraryFlat") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("CLibraryFlat".soname))
        }
    }
    
    func testSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("CLibrarySources".soname))
        }
    }
    
    func testMixedSwiftAndC() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build/debug").appending("SeaLib".soname))
            XCTAssertFileExists(prefix.appending(".build/debug").appending("SeaExec"))
            var output = try popen([prefix.appending(".build/debug").appending("SeaExec").asString])
            XCTAssertEqual(output, "a = 5\n")
            output = try popen([prefix.appending(".build/debug").appending("CExec").asString])
            XCTAssertEqual(output, "5")
        }
    }
    
    func testExternalSimpleCDep() {
        fixture(name: "DependencyResolution/External/SimpleCDep") { prefix in
            XCTAssertBuilds(prefix.appending("Bar"))
            XCTAssertFileExists(prefix.appending("Bar/.build/debug").appending("Bar"))
            XCTAssertFileExists(prefix.appending("Bar/.build/debug").appending("Foo".soname))
            XCTAssertDirectoryExists(prefix.appending("Bar/Packages/Foo-1.2.3"))
        }
    }
    
    func testiquoteDep() {
        fixture(name: "ClangModules/CLibraryiquote") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build/debug").appending("Foo".soname))
            XCTAssertFileExists(prefix.appending(".build/debug").appending("Bar".soname))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Bar with spaces".soname))
        }
    }
    
    func testCUsingCDep() {
        fixture(name: "DependencyResolution/External/CUsingCDep") { prefix in
            XCTAssertBuilds(prefix.appending("Bar"))
            XCTAssertFileExists(prefix.appending("Bar/.build/debug").appending("Foo".soname))
            XCTAssertDirectoryExists(prefix.appending("Bar/Packages/Foo-1.2.3"))
        }
    }
    
    func testCExecutable() {
        fixture(name: "ValidLayouts/SingleModule/CExecutable") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build/debug/CExecutable"))
            let output = try popen([prefix.appending(".build/debug/CExecutable").asString])
            XCTAssertEqual(output, "hello 5")
        }
    }
    
    func testCUsingCDep2() {
        //The C dependency "Foo" has different layout
        fixture(name: "DependencyResolution/External/CUsingCDep2") { prefix in
            XCTAssertBuilds(prefix.appending("Bar"))
            XCTAssertFileExists(prefix.appending("Bar/.build/debug").appending("Foo".soname))
            XCTAssertDirectoryExists(prefix.appending("Bar/Packages/Foo-1.2.3"))
        }
    }
    
    func testModuleMapGenerationCases() {
        fixture(name: "ClangModules/ModuleMapGenerationCases") { prefix in
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("UmbrellaHeader".soname))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("FlatInclude".soname))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("UmbellaModuleNameInclude".soname))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("NoIncludeDir".soname))
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("Baz"))
        }
    }

    func testCanForwardExtraFlagsToClang() {
        // Try building a fixture which needs extra flags to be able to build.
        fixture(name: "ClangModules/CDynamicLookup") { prefix in
            XCTAssertBuilds(prefix, Xld: ["-undefined", "dynamic_lookup"])
            XCTAssertFileExists(prefix.appending(".build").appending("debug").appending("CDynamicLookup".soname))
        }
    }

    static var allTests = [
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
