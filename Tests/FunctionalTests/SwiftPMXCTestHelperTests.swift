/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import TestSupport
import XCTest
import Utility
import Commands

class SwiftPMXCTestHelperTests: XCTestCase {
    func testBasicXCTestHelper() {
      #if os(macOS)
        fixture(name: "Miscellaneous/SwiftPMXCTestHelper") { prefix in
            // Build the package.
            XCTAssertBuilds(prefix)
            XCTAssertFileExists(prefix.appending(components: ".build", Destination.host.target, "debug", "SwiftPMXCTestHelper.swiftmodule"))
            // Run swift-test on package.
            XCTAssertSwiftTest(prefix)
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
            XCTAssertXCTestHelper(prefix.appending(components: ".build", Destination.host.target, "debug", "SwiftPMXCTestHelperPackageTests.xctest"), testCases: testCases)
        }
      #endif
    }
    
    static var allTests = [
        ("testBasicXCTestHelper", testBasicXCTestHelper),
    ]
}


#if os(macOS)
func XCTAssertXCTestHelper(_ bundlePath: AbsolutePath, testCases: NSDictionary) {
    do {
        let env = ["DYLD_FRAMEWORK_PATH": Resources.default.sdkPlatformFrameworksPath.asString]
        let outputFile = bundlePath.parentDirectory.appending(component: "tests.txt")
        let _ = try SwiftPMProduct.XCTestHelper.execute([bundlePath.asString, outputFile.asString], env: env, printIfError: true)
        guard let data = NSData(contentsOfFile: outputFile.asString) else {
            XCTFail("No output found in : \(outputFile.asString)"); return;
        }
        let json = try JSONSerialization.jsonObject(with: data as Data, options: []) as AnyObject
        XCTAssertTrue(json.isEqual(testCases), "\(json) is not equal to \(testCases)")
    } catch {
        XCTFail("Failed with error: \(error)")
    }
}
#endif
