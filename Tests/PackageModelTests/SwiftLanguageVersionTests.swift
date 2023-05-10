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

import XCTest

import PackageModel

class SwiftLanguageVersionTests: XCTestCase {

    func testBasics() throws {

        let validVersions = [
            "4"     : "4",
            "4.0"   : "4.0",
            "4.2"   : "4.2",
            "1.0.0" : "1.0.0",
            "3.1.0" : "3.1.0",
        ]

        for (version, expected) in validVersions {
            guard let swiftVersion = SwiftLanguageVersion(string: version) else {
                return XCTFail("Couldn't form a version with string: \(version)")
            }
            XCTAssertEqual(swiftVersion.rawValue, expected)
            XCTAssertEqual(swiftVersion.description, expected)
        }

        let invalidVersions = [
            "1.2.3.4",
            "1.2-al..beta.0+bu.uni.ra",
            "1.2.33-al..beta.0+bu.uni.ra",
            ".1.0.0-x.7.z.92",
            "1.0.0-alpha.beta+",
            "1.0.0beta",
            "1.0.0-",
            "1.-2.3",
            "1.2.3d",
        ]

        for version in invalidVersions {
            if let swiftVersion = SwiftLanguageVersion(string: version) {
                XCTFail("Formed an invalid version \(swiftVersion) with string: \(version)")
            }
        }
    }

    func testComparison() {
        XCTAssertTrue(SwiftLanguageVersion(string: "4.0.1")! > SwiftLanguageVersion(string: "4")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.0")! == SwiftLanguageVersion(string: "4")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.1")! > SwiftLanguageVersion(string: "4")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "5")! >= SwiftLanguageVersion(string: "4")!)

        XCTAssertTrue(SwiftLanguageVersion(string: "4.0.1")! < ToolsVersion(string: "4.1")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4")! == ToolsVersion(string: "4.0")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.2")! == ToolsVersion(string: "4.2")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.2")! < ToolsVersion(string: "4.3")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.2")! <= ToolsVersion(string: "4.3")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4.2")! <= ToolsVersion(string: "5.0")!)
        XCTAssertTrue(SwiftLanguageVersion(string: "4")! < ToolsVersion(string: "5.0")!)
    }
}
