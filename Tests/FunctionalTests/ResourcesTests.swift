/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import SPMTestSupport

import TSCBasic

class ResourcesTests: XCTestCase {
    func testSimpleResources() {
      #if os(macOS)
        fixture(name: "Resources/Simple") { prefix in
            try executeSwiftBuild(prefix)

            for execName in ["SwiftyResource", "SeaResource"] {
                let exec = prefix.appending(RelativePath(".build/debug/\(execName)"))
                let output = try Process.checkNonZeroExit(args: exec.pathString)
                XCTAssertTrue(output.contains("foo"), output)
            }
        }
      #endif
    }
}
