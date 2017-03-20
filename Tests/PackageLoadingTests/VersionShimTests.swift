/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import struct PackageDescription4.Version
import struct Utility.Version
import PackageLoading

fileprivate typealias PD4Version = PackageDescription4.Version
fileprivate typealias UVersion = Utility.Version

class VersionShimTests: XCTestCase {
    
    func testBasics() {
        // Ensure we can correctly convert PackageDescription's Version to our Utility's Version.
        XCTAssertEqual(UVersion(pdVersion: PD4Version("1.0.4")), UVersion(1, 0, 4))
        XCTAssertEqual(UVersion(pdVersion: PD4Version("4.3.4-alpha")), UVersion(4, 3, 4, prereleaseIdentifiers: ["alpha"]))
        XCTAssertEqual(UVersion(pdVersion: PD4Version("4.3.4-alpha.1+k")),
            UVersion(4, 3, 4, prereleaseIdentifiers: ["alpha", "1"], buildMetadataIdentifiers: ["k"]))

        // Ensure we can convert Range correctly.
        let r1: Range<PD4Version> = "1.0.4" ..< "2.0.0"
        let r2: Range<UVersion>  = "1.0.4" ..< "2.0.0"
        XCTAssertEqual(r1.asUtilityVersion, r2)
    }

    static var allTests = [
        ("testBasics", testBasics),
    ]
}
