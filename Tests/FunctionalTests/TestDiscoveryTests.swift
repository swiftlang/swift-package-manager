/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class TestDiscoveryTests: XCTestCase {
    func testBuild() throws {
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (stdout, _) = try executeSwiftBuild(fixturePath)
            // in "swift build" build output goes to stdout
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    func testDiscovery() throws {
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (stdout, stderr) = try executeSwiftTest(fixturePath)
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("Executed 3 tests"))
        }
    }

    func testNonStandardName() throws {
        try fixture(name: "Miscellaneous/TestDiscovery/hello world") { fixturePath in
            let (stdout, stderr) = try executeSwiftTest(fixturePath)
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("Executed 1 test"))
        }
    }

    func testAsyncMethods() throws {
        try fixture(name: "Miscellaneous/TestDiscovery/Async") { fixturePath in
            let (stdout, stderr) = try executeSwiftTest(fixturePath)
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("Executed 4 tests"))
        }
    }

    func testManifestOverride() throws {
        #if os(macOS)
        try XCTSkipIf(true)
        #endif
        try SwiftTarget.testManifestNames.forEach { name in
            try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let random = UUID().uuidString
                let manifestPath = fixturePath.appending(components: "Tests", name)
                try localFileSystem.writeFileContents(manifestPath, bytes: ByteString("print(\"\(random)\")".utf8))
                let (stdout, stderr) = try executeSwiftTest(fixturePath)
                // in "swift test" build output goes to stderr
                XCTAssertMatch(stderr, .contains("Build complete!"))
                // in "swift test" test output goes to stdout
                XCTAssertNoMatch(stdout, .contains("Executed 1 test"))
                XCTAssertMatch(stdout, .contains(random))
            }
        }
    }

    func testManifestOverrideIgnored() throws {
        #if os(macOS)
        try XCTSkipIf(true)
        #endif
        let name = SwiftTarget.testManifestNames.first!
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let manifestPath = fixturePath.appending(components: "Tests", name)
            try localFileSystem.writeFileContents(manifestPath, bytes: ByteString("fatalError(\"should not be called\")".utf8))
            let (stdout, stderr) = try executeSwiftTest(fixturePath, extraArgs: ["--enable-test-discovery"])
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("Executed 1 test"))
        }
    }

    func testTestExtensions() throws {
        #if os(macOS)
        try XCTSkipIf(true)
        #endif
        try fixture(name: "Miscellaneous/TestDiscovery/Extensions") { fixturePath in
            let (stdout, stderr) = try executeSwiftTest(fixturePath)
            // in "swift test" build output goes to stderr
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("SimpleTests1.testExample1"))
            XCTAssertMatch(stdout, .contains("SimpleTests1.testExample1_a"))
            XCTAssertMatch(stdout, .contains("SimpleTests2.testExample2"))
            XCTAssertMatch(stdout, .contains("SimpleTests2.testExample2_a"))
            XCTAssertMatch(stdout, .contains("SimpleTests4.testExample"))
            XCTAssertMatch(stdout, .contains("SimpleTests4.testExample1"))
            XCTAssertMatch(stdout, .contains("SimpleTests4.testExample2"))
            XCTAssertMatch(stdout, .contains("Executed 7 tests"))
        }
    }

    func testDeprecatedTests() throws {
        #if os(macOS)
        try XCTSkipIf(true)
        #endif
        try fixture(name: "Miscellaneous/TestDiscovery/Deprecation") { fixturePath in
            let (stdout, stderr) = try executeSwiftTest(fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("Executed 2 tests"))
            XCTAssertNoMatch(stderr, .contains("is deprecated"))
        }
    }
}
