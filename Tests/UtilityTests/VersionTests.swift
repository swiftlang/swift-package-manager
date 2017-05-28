/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Version
import XCTest

class VersionTests: XCTestCase {

    func testEquality() {
        let versions: [Version] = ["1.2.3", "0.0.0",
            "0.0.0-alpha+yol", "0.0.0-alpha.1+pol",
            "0.1.2", "10.7.3",
        ]
        // Test that each version is equal to itself and not equal to others.
        for (idx, version) in versions.enumerated() {
            for (ridx, rversion) in versions.enumerated() {
                if idx == ridx {
                    XCTAssertEqual(version, rversion)
                    // Construct the object again with different initializer.
                    XCTAssertEqual(version,
                        Version(rversion.major, rversion.minor, rversion.patch,
                            prereleaseIdentifiers: rversion.prereleaseIdentifiers,
                            buildMetadataIdentifiers: rversion.buildMetadataIdentifiers))
                } else {
                    XCTAssertNotEqual(version, rversion)
                }
            }
        }
    }

    func testHashable() {
        let versions: [Version] = ["1.2.3", "1.2.3", "1.2.3",
            "1.0.0-alpha", "1.0.0-alpha",
            "1.0.0", "1.0.0"
        ]
        XCTAssertEqual(Set(versions), Set(["1.0.0-alpha", "1.2.3", "1.0.0"]))

        XCTAssertEqual(Set([Version(1,2,3)]), Set([Version(1,2,3)]))
        XCTAssertNotEqual(Set([Version(1,2,3)]), Set([Version(1,2,3, prereleaseIdentifiers: ["alpha"])]))
        XCTAssertNotEqual(Set([Version(1,2,3)]), Set([Version(1,2,3, buildMetadataIdentifiers: ["1011"])]))
    }

    func testDescription() {
        let v: Version = "123.234.345-alpha.beta+sha1.1011"
        XCTAssertEqual(v.description, "123.234.345-alpha.beta+sha1.1011")
        XCTAssertEqual(v.major, 123)
        XCTAssertEqual(v.minor, 234)
        XCTAssertEqual(v.patch, 345)
        XCTAssertEqual(v.prereleaseIdentifiers, ["alpha", "beta"])
        XCTAssertEqual(v.buildMetadataIdentifiers, ["sha1", "1011"])
    }

    func testFromString() {
        let badStrings = [
            "", "1", "1.2", "1.2.3.4", "1.2.3.4.5",
            "a", "1.a", "a.2", "a.2.3", "1.a.3", "1.2.a",
            "-1.2.3", "1.-2.3", "1.2.-3", ".1.2.3", "v.1.2.3", "1.2..3", "v1.2.3",
        ]
        for str in badStrings {
            XCTAssertNil(Version(string: str))
        }

        XCTAssertEqual(Version(1,2,3), Version(string: "1.2.3"))
        XCTAssertEqual(Version(1,2,3), Version(string: "01.002.0003"))
        XCTAssertEqual(Version(0,9,21), Version(string: "0.9.21"))
        XCTAssertEqual(Version(0,9,21, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifiers: ["1011"]),
            Version(string: "0.9.21-alpha.beta+1011"))
        XCTAssertEqual(Version(0,9,21, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1011"]), Version(string: "0.9.21+1011"))
    }

    func testComparable() {
        do {
            let v1 = Version(1,2,3)
            let v2 = Version(2,1,2)
            XCTAssertLessThan(v1, v2)
            XCTAssertLessThanOrEqual(v1, v2)
            XCTAssertGreaterThan(v2, v1)
            XCTAssertGreaterThanOrEqual(v2, v1)
            XCTAssertNotEqual(v1, v2)

            XCTAssertLessThanOrEqual(v1, v1)
            XCTAssertGreaterThanOrEqual(v1, v1)
            XCTAssertLessThanOrEqual(v2, v2)
            XCTAssertGreaterThanOrEqual(v2, v2)
        }

        do {
            let v3 = Version(2,1,3)
            let v4 = Version(2,2,2)
            XCTAssertLessThan(v3, v4)
            XCTAssertLessThanOrEqual(v3, v4)
            XCTAssertGreaterThan(v4, v3)
            XCTAssertGreaterThanOrEqual(v4, v3)
            XCTAssertNotEqual(v3, v4)

            XCTAssertLessThanOrEqual(v3, v3)
            XCTAssertGreaterThanOrEqual(v3, v3)
            XCTAssertLessThanOrEqual(v4, v4)
            XCTAssertGreaterThanOrEqual(v4, v4)
        }

        do {
            let v5 = Version(2,1,2)
            let v6 = Version(2,1,3)
            XCTAssertLessThan(v5, v6)
            XCTAssertLessThanOrEqual(v5, v6)
            XCTAssertGreaterThan(v6, v5)
            XCTAssertGreaterThanOrEqual(v6, v5)
            XCTAssertNotEqual(v5, v6)

            XCTAssertLessThanOrEqual(v5, v5)
            XCTAssertGreaterThanOrEqual(v5, v5)
            XCTAssertLessThanOrEqual(v6, v6)
            XCTAssertGreaterThanOrEqual(v6, v6)
        }

        do {
            let v7 = Version(0,9,21)
            let v8 = Version(2,0,0)
            XCTAssert(v7 < v8)
            XCTAssertLessThan(v7, v8)
            XCTAssertLessThanOrEqual(v7, v8)
            XCTAssertGreaterThan(v8, v7)
            XCTAssertGreaterThanOrEqual(v8, v7)
            XCTAssertNotEqual(v7, v8)

            XCTAssertLessThanOrEqual(v7, v7)
            XCTAssertGreaterThanOrEqual(v7, v7)
            XCTAssertLessThanOrEqual(v8, v8)
            XCTAssertGreaterThanOrEqual(v8, v8)
        }

        do {
            // Prerelease precedence tests taken directly from http://semver.org
            var tests: [Version] = [
                "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"
            ]

            var v1 = tests.removeFirst()
            for v2 in tests {
                XCTAssertLessThan(v1, v2)
                XCTAssertLessThanOrEqual(v1, v2)
                XCTAssertGreaterThan(v2, v1)
                XCTAssertGreaterThanOrEqual(v2, v1)
                XCTAssertNotEqual(v1, v2)

                XCTAssertLessThanOrEqual(v1, v1)
                XCTAssertGreaterThanOrEqual(v1, v1)
                XCTAssertLessThanOrEqual(v2, v2)
                XCTAssertGreaterThanOrEqual(v2, v2)

                v1 = v2
            }
        }
    }

    func testOrder() {
        XCTAssertLessThan(Version(0,0,0), Version(0,0,1))
        XCTAssertLessThan(Version(0,0,1), Version(0,1,0))
        XCTAssertLessThan(Version(0,1,0), Version(0,10,0))
        XCTAssertLessThan(Version(0,10,0), Version(1,0,0))
        XCTAssertLessThan(Version(1,0,0), Version(2,0,0))
        XCTAssert(!(Version(1,0,0) < Version(1,0,0)))
        XCTAssert(!(Version(2,0,0) < Version(1,0,0)))
    }

    func testRange() {
        switch Version(1,2,4) {
        case Version(1,2,3)..<Version(2,3,4):
            break
        default:
            XCTFail()
        }

        switch Version(1,2,4) {
        case Version(1,2,3)..<Version(2,3,4):
            break
        case Version(1,2,5)..<Version(1,2,6):
            XCTFail()
        default:
            XCTFail()
        }

        switch Version(1,2,4) {
        case Version(1,2,3)..<Version(1,2,4):
            XCTFail()
        case Version(1,2,5)..<Version(1,2,6):
            XCTFail()
        default:
            break
        }

        switch Version(1,2,4) {
        case Version(1,2,5)..<Version(2,0,0):
            XCTFail()
        case Version(2,0,0)..<Version(2,2,6):
            XCTFail()
        case Version(0,0,1)..<Version(0,9,6):
            XCTFail()
        default:
            break
        }
    }

    func testContains() {
        do {
            let range: Range<Version> = "1.0.0"..<"2.0.0"

            XCTAssertTrue(range.contains(version: "1.0.0"))
            XCTAssertTrue(range.contains(version: "1.5.0"))
            XCTAssertTrue(range.contains(version: "1.9.99999"))
            XCTAssertTrue(range.contains(version: "1.9.99999+1232"))

            XCTAssertFalse(range.contains(version: "1.0.0-alpha"))
            XCTAssertFalse(range.contains(version: "1.5.0-alpha"))
            XCTAssertFalse(range.contains(version: "2.0.0-alpha"))
            XCTAssertFalse(range.contains(version: "2.0.0"))
        }

        do {
            let range: Range<Version> = "1.0.0"..<"2.0.0-beta"

            XCTAssertTrue(range.contains(version: "1.0.0"))
            XCTAssertTrue(range.contains(version: "1.5.0"))
            XCTAssertTrue(range.contains(version: "1.9.99999"))
            XCTAssertTrue(range.contains(version: "1.0.1-alpha"))
            XCTAssertTrue(range.contains(version: "2.0.0-alpha"))

            XCTAssertFalse(range.contains(version: "1.0.0-alpha"))
            XCTAssertFalse(range.contains(version: "2.0.0"))
            XCTAssertFalse(range.contains(version: "2.0.0-beta"))
            XCTAssertFalse(range.contains(version: "2.0.0-clpha"))
        }

        do {
            let range: Range<Version> = "1.0.0-alpha"..<"2.0.0"
            XCTAssertTrue(range.contains(version: "1.0.0"))
            XCTAssertTrue(range.contains(version: "1.5.0"))
            XCTAssertTrue(range.contains(version: "1.9.99999"))
            XCTAssertTrue(range.contains(version: "1.0.0-alpha"))
            XCTAssertTrue(range.contains(version: "1.0.0-beta"))
            XCTAssertTrue(range.contains(version: "1.0.1-alpha"))

            XCTAssertFalse(range.contains(version: "2.0.0-alpha"))
            XCTAssertFalse(range.contains(version: "2.0.0-beta"))
            XCTAssertFalse(range.contains(version: "2.0.0-clpha"))
            XCTAssertFalse(range.contains(version: "2.0.0"))
        }

        do {
            let range: Range<Version> = "1.0.0"..<"1.1.0"
            XCTAssertTrue(range.contains(version: "1.0.0"))
            XCTAssertTrue(range.contains(version: "1.0.9"))

            XCTAssertFalse(range.contains(version: "1.1.0"))
            XCTAssertFalse(range.contains(version: "1.2.0"))
            XCTAssertFalse(range.contains(version: "1.5.0"))
            XCTAssertFalse(range.contains(version: "2.0.0"))
            XCTAssertFalse(range.contains(version: "1.0.0-beta"))
            XCTAssertFalse(range.contains(version: "1.0.10-clpha"))
            XCTAssertFalse(range.contains(version: "1.1.0-alpha"))
        }

        do {
            let range: Range<Version> = "1.0.0"..<"1.1.0-alpha"
            XCTAssertTrue(range.contains(version: "1.0.0"))
            XCTAssertTrue(range.contains(version: "1.0.9"))
            XCTAssertTrue(range.contains(version: "1.0.1-beta"))
            XCTAssertTrue(range.contains(version: "1.0.10-clpha"))

            XCTAssertFalse(range.contains(version: "1.1.0"))
            XCTAssertFalse(range.contains(version: "1.2.0"))
            XCTAssertFalse(range.contains(version: "1.5.0"))
            XCTAssertFalse(range.contains(version: "2.0.0"))
            XCTAssertFalse(range.contains(version: "1.0.0-alpha"))
            XCTAssertFalse(range.contains(version: "1.1.0-alpha"))
            XCTAssertFalse(range.contains(version: "1.1.0-beta"))
        }
    }

    static var allTests = [
        ("testEquality", testEquality),
        ("testHashable", testHashable),
        ("testComparable", testComparable),
        ("testDescription", testDescription),
        ("testFromString", testFromString),
        ("testOrder", testOrder),
        ("testRange", testRange),
        ("testContains", testContains),
    ]
}
