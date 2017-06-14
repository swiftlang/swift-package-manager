/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import Basic
import libc
import Utility
import TestSupport

class InterruptHandlerTests: XCTestCase {
    func testBasics() throws {
        // Disabled because it sometimes hangs the CI, possibly due to https://bugs.swift.org/browse/SR-5042
      #if false
        mktmpdir { path in
            let exec = SwiftPMProduct.TestSupportExecutable.path.asString
            let waitFile = path.appending(component: "waitFile")
            let process = Process(args: exec, "interruptHandlerTest", waitFile.asString)
            try process.launch()
            guard waitForFile(waitFile) else {
                return XCTFail("Couldn't launch the process")
            }
            process.signal(SIGINT)
            let result = try process.waitUntilExit()
            XCTAssertEqual(try result.utf8Output(), "Hello from handler!\n")
        }
      #endif
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
