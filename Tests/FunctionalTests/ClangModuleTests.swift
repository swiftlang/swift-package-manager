/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
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

extension String {
    // FIXME: It doesn't seem right for this to be an extension on String; it isn't inherent "string behavior".
    fileprivate var soname: String {
        return "lib\(self).\(Product.dynamicLibraryExtension)"
    }
}

class ClangModulesTestCase: XCTestCase {
    func testSingleModuleFlatCLibrary() {
        fixture(name: "ClangModules/CLibraryFlat") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(components: "CLibraryFlat".soname))
        }
    }
    
    func testSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "CLibrarySources".soname))
        }
    }
    
    func testMixedSwiftAndC() {
        fixture(name: "ClangModules/SwiftCMixed") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "SeaLib".soname))
            XCTAssertFileExists(debugPath.appending(component: "SeaExec"))
            var output = try popen([debugPath.appending(component: "SeaExec").asString])
            XCTAssertEqual(output, "a = 5\n")
            output = try popen([debugPath.appending(component: "CExec").asString])
            XCTAssertEqual(output, "5")
        }
    }
    
    func testExternalSimpleCDep() {
        fixture(name: "DependencyResolution/External/SimpleCDep") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "Bar"))
            XCTAssertFileExists(debugPath.appending(component: "Foo".soname))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testiquoteDep() {
        fixture(name: "ClangModules/CLibraryiquote") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "Foo".soname))
            XCTAssertFileExists(debugPath.appending(component: "Bar".soname))
            XCTAssertFileExists(debugPath.appending(component: "Bar with spaces".soname))
        }
    }
    
    func testCUsingCDep() {
        fixture(name: "DependencyResolution/External/CUsingCDep") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "Foo".soname))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testCExecutable() {
        fixture(name: "ValidLayouts/SingleModule/CExecutable") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "CExecutable"))
            let output = try popen([debugPath.appending(component: "CExecutable").asString])
            XCTAssertEqual(output, "hello 5")
        }
    }
    
    func testCUsingCDep2() {
        //The C dependency "Foo" has different layout
        fixture(name: "DependencyResolution/External/CUsingCDep2") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            XCTAssertBuilds(packageRoot)
            let debugPath = prefix.appending(components: "Bar", ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "Foo".soname))
            let path = try SwiftPMProduct.packagePath(for: "Foo", packageRoot: packageRoot)
            XCTAssertEqual(GitRepository(path: path).tags, ["1.2.3"])
        }
    }
    
    func testModuleMapGenerationCases() {
        fixture(name: "ClangModules/ModuleMapGenerationCases") { prefix in
            XCTAssertBuilds(prefix)
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "UmbrellaHeader".soname))
            XCTAssertFileExists(debugPath.appending(component: "FlatInclude".soname))
            XCTAssertFileExists(debugPath.appending(component: "UmbellaModuleNameInclude".soname))
            XCTAssertFileExists(debugPath.appending(component: "NoIncludeDir".soname))
            XCTAssertFileExists(debugPath.appending(component: "Baz"))
        }
    }

    func testCanForwardExtraFlagsToClang() {
        // Try building a fixture which needs extra flags to be able to build.
        fixture(name: "ClangModules/CDynamicLookup") { prefix in
            XCTAssertBuilds(prefix, Xld: ["-undefined", "dynamic_lookup"])
            let debugPath = prefix.appending(components: ".build", "debug")
            XCTAssertFileExists(debugPath.appending(component: "CDynamicLookup".soname))
        }
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
    ]
}
