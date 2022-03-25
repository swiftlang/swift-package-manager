//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Commands
import PackageModel
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

class SwiftPMXCTestHelperTests: XCTestCase {
    func testBasicXCTestHelper() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/SwiftPMXCTestHelper") { fixturePath in
            // Build the package.
            XCTAssertBuilds(fixturePath)
            let triple = UserToolchain.default.triple
            XCTAssertFileExists(fixturePath.appending(components: ".build", triple.platformBuildPathComponent(), "debug", "SwiftPMXCTestHelper.swiftmodule"))
            // Run swift-test on package.
            XCTAssertSwiftTest(fixturePath)
            // Expected output dictionary.
            let testCases = ["name": "All Tests", "tests": [["name" : "SwiftPMXCTestHelperPackageTests.xctest",
                "tests": [
                [
                "name": "ObjCTests",
                "tests": [["name": "test_example"], ["name": "testThisThing"]] as Array<Dictionary<String, String>>
                ],
                [
                "name": "SwiftPMXCTestHelperTests.SwiftPMXCTestHelperTests1",
                "tests": [["name": "test_Example2"], ["name": "testExample1"]] as Array<Dictionary<String, String>>
                ]
              ] as Array<Dictionary<String, Any>>]] as Array<Dictionary<String, Any>>
            ] as Dictionary<String, Any> as NSDictionary
            // Run the XCTest helper tool and check result.
            try XCTAssertXCTestHelper(fixturePath.appending(components: ".build", UserToolchain.default.triple.platformBuildPathComponent(), "debug", "SwiftPMXCTestHelperPackageTests.xctest"), testCases: testCases)
        }
    }

    func XCTAssertXCTestHelper(_ bundlePath: AbsolutePath, testCases: NSDictionary) throws {
        #if os(macOS)
        let env = ["DYLD_FRAMEWORK_PATH": UserToolchain.default.sdkPlatformFrameworksPath.pathString]
        let outputFile = bundlePath.parentDirectory.appending(component: "tests.txt")
        let _ = try SwiftPMProduct.XCTestHelper.execute([bundlePath.pathString, outputFile.pathString], env: env)
        guard let data = NSData(contentsOfFile: outputFile.pathString) else {
            XCTFail("No output found in : \(outputFile)"); return;
        }
        let json = try JSONSerialization.jsonObject(with: data as Data, options: []) as AnyObject
        XCTAssertTrue(json.isEqual(testCases), "\(json) is not equal to \(testCases)")
        #else
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
    }
}
