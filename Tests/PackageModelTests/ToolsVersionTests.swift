/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import PackageModel

class ToolsVersionTests: XCTestCase {

    func testBasics() throws {

        let validVersions = [
            "3.1.0"                         : "3.1.0",
            "4.0"                           : "4.0.0",
            "0000104.0000000.4444"          : "104.0.4444",
            "1.2.3-alpha.beta+1011"         : "1.2.3",
            "1.2-alpha.beta+1011"           : "1.2.0",
            "1.0.0-alpha+001"               : "1.0.0",
            "1.0.0+20130313144700"          : "1.0.0",
            "1.0.0-beta+exp.sha.5114f85"    : "1.0.0",
            "1.0.0-alpha"                   : "1.0.0",
            "1.0.0-alpha.1"                 : "1.0.0",
            "1.0.0-0.3.7"                   : "1.0.0",
            "1.0.0-x.7.z.92"                : "1.0.0",
            "1.0.0-alpha.beta"              : "1.0.0",
            "1.0.0-beta"                    : "1.0.0",
            "1.0.0-beta.2"                  : "1.0.0",
            "1.0.0-beta.11"                 : "1.0.0",
            "1.0.0-rc.1"                    : "1.0.0",
            "1.0.0"                         : "1.0.0",
            "1.2.3-4"                       : "1.2.3",
            "2.7.2+asdf"                    : "2.7.2",
            "1.2.3-a.b.c.10.d.5"            : "1.2.3",
            "2.7.2-foo+bar"                 : "2.7.2",
            "1.2.3-alpha.10.beta.0"         : "1.2.3",
            "1.2.3-al.10.beta.0+bu.uni.ra"  : "1.2.3",
            "1.2-al.10.beta.0+bu.uni.ra"    : "1.2.0",
        ]

        for (version, expected) in validVersions {
            guard let toolsVersion = ToolsVersion(string: version) else {
                return XCTFail("Couldn't form a version with string: \(version)")
            }
            XCTAssertEqual(toolsVersion.description, expected)
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
            if let toolsVersion = ToolsVersion(string: version) {
                XCTFail("Form an invalid version \(toolsVersion) with string: \(version)")
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
