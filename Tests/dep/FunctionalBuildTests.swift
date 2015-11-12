/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import dep
import struct PackageDescription.Version
import func POSIX.popen
import sys
import XCTest

class FunctionalBuildTests: SandboxTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testSingleLibTarget", testSingleLibTarget),
            ("testMultipleLibTargets", testMultipleLibTargets),
            ("testSingleExecTarget", testSingleExecTarget),
            ("testMultipleExecTargets", testMultipleExecTargets),
            ("testMultipleLibAndExecTargets", testMultipleLibAndExecTargets),
            ("testSingleLibTargetInSources", testSingleLibTargetInSources),
            ("testMultipleLibTargetsInSources", testMultipleLibTargetsInSources),
            ("testSingleExecTargetInSources", testSingleExecTargetInSources),
            ("testMultipleExecTargetsInSources", testMultipleExecTargetsInSources),
            ("testMultipleLibAndExecTargetsInSources", testMultipleLibAndExecTargetsInSources),
            ("testSingleLibTargetSrc", testSingleLibTargetSrc),
            ("testMultipleLibTargetsSrc", testMultipleLibTargetsSrc),
            ("testSingleExecTargetSrc", testSingleExecTargetSrc),
            ("testMultipleExecTargetsSrc", testMultipleExecTargetsSrc),
            ("testMultipleExecTargetsSourcesSrc", testMultipleExecTargetsSourcesSrc),
            ("testMultipleLibTargetsSourcesSrc", testMultipleLibTargetsSourcesSrc),
            ("testMultipleLibExecTargetsSourcesSrc", testMultipleLibExecTargetsSourcesSrc),
            ("testMultipleLibExecTargetsSourcesSrcExt", testMultipleLibExecTargetsSourcesSrcExt),
        ]
    }
    
    func runBuildTest(fixtureName: String, files:[String]) {
        let version = Version(1,0,0)
        let mock = MockPackage(fixtureName: fixtureName, version: version)
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertEqual(try! executeSwiftBuild(), 0)
            self.verifyFilesExist(files, fixturePath: sandboxPath + "/.build/debug")
        }
    }
    
    func verifyFilesExist(files: [String], fixturePath: String) {
        for file in files {
            let filePath: String
            // Capture lib/executable names of targets that aren't in subfolders
            let pathComponents = fixturePath.characters.split("/").map(String.init)
            
            switch file {
                // Target (library) not in subfolder
            case "rootLib":
                filePath = fixturePath + "/" + pathComponents.reverse()[2] + ".a"
                // Target (executable) not in subfolder
            case "rootExec":
                filePath = fixturePath + "/" + pathComponents.reverse()[2]
            default:
                filePath = fixturePath + "/\(file)"
            }
            
            XCTAssertTrue(filePath.isFile, filePath)
        }
    }
    
    func testIgnoreFiles() {
        let mock = MockPackage(fixtureName: "20_ignore_files", version: Version(1,0,0))
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertEqual(try! executeSwiftBuild(), 0)
            
            let targets = try! determineTargets(packageName: "foo", prefix: mock.path)
            
            XCTAssertEqual(targets.count, 1)
            XCTAssertEqual(targets[0].sources.map({ $0.basename }), ["Foo.swift"])
        }
    }
    
    // 2: Package with one library target
    func testSingleLibTarget() {
        let filesToVerify = ["rootLib"]
        runBuildTest("2_buildlib_single_target", files: filesToVerify)
    }
    
    
    // 3: Package with multiple library targets
    func testMultipleLibTargets() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        runBuildTest("3_buildlib_mult_targets", files: filesToVerify)
    }
    
    
    // 4: Package with one executable target
    func testSingleExecTarget() {
        let filesToVerify = ["rootExec"]
        runBuildTest("4_buildexec_single_target", files: filesToVerify)
    }
    
    
    // 5: Package with multiple exectuble targets
    func testMultipleExecTargets() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        runBuildTest("5_buildexec_mult_targets", files: filesToVerify)
    }
    
    
    // 6: Package with multiple library and executable targets
    func testMultipleLibAndExecTargets() {
        let filesToVerify = ["BarExec", "BarFooLib.a", "FooBarLib.a", "FooExec"]
        runBuildTest("6_buildexeclib_mult_targets", files: filesToVerify)
    }
    
    
    // 7: Package with a single library target in a sources directory
    func testSingleLibTargetInSources() {
        let filesToVerify = ["rootLib"]
        runBuildTest("7_buildlib_sources_single_target", files: filesToVerify)
    }
    
    
    // 8: Package with multiple library targets in a sources directory
    func testMultipleLibTargetsInSources() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        runBuildTest("8_buildlib_sources_mult_targets", files: filesToVerify)
    }
    
    
    // 9: Package with a single executable target in a sources directory
    func testSingleExecTargetInSources() {
        let filesToVerify = ["rootExec"]
        runBuildTest("9_buildexec_sources_single_target", files: filesToVerify)
    }
    
    
    // 10: Package with multiple executable targets in a sources directory
    func testMultipleExecTargetsInSources() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        runBuildTest("10_buildexec_sources_mult_targets", files: filesToVerify)
    }
    
    
    // 11: Package with multiple library and executable targets in a sources directory
    func testMultipleLibAndExecTargetsInSources() {
        let filesToVerify = ["BarFooExec", "BarLib.a", "FooBarExec", "FooLib.a"]
        runBuildTest("11_buildexeclib_sources_mult_targets", files: filesToVerify)
    }
    
    
    // 12: Package with a single library targets in a src directory
    func testSingleLibTargetSrc() {
        let filesToVerify = ["rootLib"]
        runBuildTest("12_buildlib_src_single_target", files: filesToVerify)
    }
    
    
    // 13: Package with multiple library targets in a src directory
    func testMultipleLibTargetsSrc() {
        let filesToVerify = ["BarLib.a", "FooBarLib.a", "FooLib.a"]
        runBuildTest("13_buildlib_src_mult_targets", files: filesToVerify)
    }
    
    
    // 14: Package with a single executable target in a src directory
    func testSingleExecTargetSrc() {
        let filesToVerify = ["rootExec"]
        runBuildTest("14_buildexec_src_single_target", files: filesToVerify)
    }
    
    
    // 15: Package with multiple executable targets in src directory
    func testMultipleExecTargetsSrc() {
        let filesToVerify = ["BarExec", "FooBarExec", "FooExec"]
        runBuildTest("15_buildexec_src_mult_targets", files: filesToVerify)
    }
    
    
    // 16: Package with multiple executable targets in a sources and src directory
    func testMultipleExecTargetsSourcesSrc() {
        let mock = MockPackage(fixtureName: "16_buildexec_src_sources", version: Version(1,0,0))
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertNotEqual(try! executeSwiftBuild(), 0)
        }
    }
    
    
    // 17: Package with multiple library targets in a sources and src directory
    func testMultipleLibTargetsSourcesSrc() {
        let mock = MockPackage(fixtureName: "17_buildlib_src_sources", version: Version(1,0,0))
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertNotEqual(try! executeSwiftBuild(), 0)
        }
    }
    
    
    // 18: Package with multiple executable and library targets in a sources and src directory
    func testMultipleLibExecTargetsSourcesSrc() {
        let mock = MockPackage(fixtureName: "18_buildlibexec_src_sources", version: Version(1,0,0))
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertNotEqual(try! executeSwiftBuild(), 0)
        }
    }
    
    
    // 19: Package with multiple executable and library targets in a sources and src directory, and externally
    func testMultipleLibExecTargetsSourcesSrcExt() {
        let mock = MockPackage(fixtureName: "19_buildlibexec_src_sources_external", version: Version(1,0,0))
        
        createSandbox(forPackage: mock) { sandboxPath, executeSwiftBuild in
            XCTAssertNotEqual(try! executeSwiftBuild(), 0)
        }
    }
    
    
    // 20: Single dependency where BarLib depends on FooLib
    func testLibDep() {
        let filesToVerify = ["BarLib.a", "FooLib.a"]
        runBuildTest("20_buildlib_singledep", files: filesToVerify)
    }
    
    
    // 21: Multiple dependencies where BarLib depends on FooLib and FooBarLib
    func testLibDeps() {
        let filesToVerify = ["BarLib.a", "FooLib.a", "FooBarLib.a"]
        runBuildTest("21_buildlib_multdep", files: filesToVerify)
    }
    
    
    // 22: Single dependency where Foo executable depends on Foo library
    func testExecDep() {
        let filesToVerify = ["FooLib.a", "FooExec"]
        runBuildTest("22_buildexec_singledep", files: filesToVerify)
    }
    
    
    // 23: Multiple dependencies where Foo executable depends on two libraries
    func testExecDeps() {
        let filesToVerify = ["FooExec", "FooLib1.a", "FooLib2.a"]
        runBuildTest("23_buildexec_multdep", files: filesToVerify)
    }
    
    // 24: Multiple dependencies
    func testMultDeps() {
        let filesToVerify = ["Bar.a", "BarLib.a", "DepOnFooExec", "DepOnFooLib.a", "Foo", "FooLib.a"]
        runBuildTest("24_buildexeclib_deps", files: filesToVerify)
    }
    
    // 25: Build Mattt's Dealer
    func testDealerBuild() {
        testSwiftGet(fixtureName: "101_mattts_dealer") { prefix, baseURL, executeSwiftGet in
            XCTAssertEqual(try! executeSwiftGet("\(baseURL)/app"), 0)
        }
    }

    // 25: Build Mattt's Dealer
    func testDealerBuildOutput() {
        testSwiftGet(fixtureName: "102_mattts_dealer") { prefix, baseURL, executeSwiftGet in
            XCTAssertEqual(try! executeSwiftGet("\(baseURL)/app"), 0)
            let output = try! popen([Path.join(prefix, "app-1.2.3/Dealer")])
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }
}
