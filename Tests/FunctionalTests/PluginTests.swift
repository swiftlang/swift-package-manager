/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import SPMTestSupport
import TSCBasic

class PluginTests: XCTestCase {
    
    func testUseOfBuildToolPluginTargetByExecutableInSamePackage() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 999.0.
        try XCTSkipUnless(doesHostSwiftCompilerSupportRenamingMainSymbol(), "skipping because host compiler doesn't support '-entry-point-function-name'")
        
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"], env: ["SWIFTPM_ENABLE_PLUGINS": "1"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testUseOfBuildToolPluginProductByExecutableAcrossPackages() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 999.0.
        try XCTSkipUnless(doesHostSwiftCompilerSupportRenamingMainSymbol(), "skipping because host compiler doesn't support '-entry-point-function-name'")

        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenClient"), configuration: .Debug, extraArgs: ["--product", "MyTool"], env: ["SWIFTPM_ENABLE_PLUGINS": "1"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testUseOfPrebuildPluginTargetByExecutableAcrossPackages() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 999.0.
        try XCTSkipUnless(doesHostSwiftCompilerSupportRenamingMainSymbol(), "skipping because host compiler doesn't support '-entry-point-function-name'")

        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenPlugin"), configuration: .Debug, extraArgs: ["--product", "MyOtherLocalTool"], env: ["SWIFTPM_ENABLE_PLUGINS": "1"])
                XCTAssert(stdout.contains("Compiling MyOtherLocalTool bar.swift"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Compiling MyOtherLocalTool baz.swift"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyOtherLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testContrivedTestCases() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 999.0.
        try XCTSkipUnless(doesHostSwiftCompilerSupportRenamingMainSymbol(), "skipping because host compiler doesn't support '-entry-point-function-name'")
        
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "ContrivedTestPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"], env: ["SWIFTPM_ENABLE_PLUGINS": "1"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

}
