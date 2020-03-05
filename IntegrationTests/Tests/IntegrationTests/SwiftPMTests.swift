/*
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCTestSupport

final class SwiftPMTests: XCTestCase {
  #if os(macOS)
    // FIXME: This is failing right now.
    func DISABLED_testBinaryTargets() throws {
        try binaryTargetsFixture { prefix in
            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", prefix, "exe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertEqual(stdout, """
                    SwiftFramework()
                    Library(framework: SwiftFramework.SwiftFramework())

                    """)
            }

            do {
                let (stdout, stderr) = try sh(swiftRun, "--package-path", prefix, "cexe")
                XCTAssertNoMatch(stderr, .contains("warning: "))
                XCTAssertMatch(stdout, .contains("<CLibrary: "))
            }

            do {
                let invalidPath = prefix.appending(component: "SwiftFramework.xcframework")
                let (_, stderr) = try shFails(swiftPackage, "--package-path", prefix, "compute-checksum", invalidPath)
                XCTAssertMatch(stderr, .contains("error: unexpected file type; supported extensions are: zip"))

                let validPath = prefix.appending(component: "SwiftFramework.zip")
                let (stdout, _) = try sh(swiftPackage, "--package-path", prefix, "compute-checksum", validPath)
                XCTAssertEqual(stdout.spm_chomp(), "d1f202b1bfe04dea30b2bc4038f8059dcd75a5a176f1d81fcaedb6d3597d1158")
            }
        }
    }
  #endif
}
