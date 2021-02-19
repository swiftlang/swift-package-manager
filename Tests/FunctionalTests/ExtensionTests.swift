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

class ExtensionTests: XCTestCase {
    
    func testSimpleSourceGeneration() {
        fixture(name: "Miscellaneous/Extensions/MySourceGenExtension") { prefix in
            do {
                let (stdout, _) = try executeSwiftBuild(prefix, configuration: .Debug, env: ["SWIFTPM_ENABLE_EXTENSION_TARGETS": "1"])
                XCTAssert(stdout.contains("Linking MySourceGenTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("MySourceGenTooling Foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build Completed"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }
}
