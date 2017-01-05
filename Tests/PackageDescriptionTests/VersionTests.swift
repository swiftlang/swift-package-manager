/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageDescription
import XCTest

class VersionTests: XCTestCase {

    func testEquality() {
        func test( _ v: @autoclosure() -> Version) {
            XCTAssertEqual(v(), v())
        }

        test(Version(1,2,3))
        test(Version(1,2,3, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011"))
        test(Version(0,0,0))
        test(Version(Int.min, Int.min, Int.min))
        test(Version(Int.max, Int.max, Int.max))
    }

    func testNegativeValuesBecomeZero() {
        XCTAssertEqual(Version(-1, -2, -3), Version(0,0,0))
    }

    func testHashable() {
        XCTAssertEqual(Set([Version(1,2,3)]), Set([Version(1,2,3)]))
        XCTAssertEqual(
            Set([Version(1,2,3, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011")]),
            Set([Version(1,2,3, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011")]))
        XCTAssertEqual(
            Set((1...4).map{ Version($0,0,0) }),
            Set((1...4).map{ Version($0,0,0) }))
        XCTAssertNotEqual(Set([Version(1,2,3)]), Set([Version(1,2,3, prereleaseIdentifiers: ["alpha"])]))
        XCTAssertNotEqual(Set([Version(1,2,3)]), Set([Version(1,2,3, buildMetadataIdentifier: "1011")]))
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
            var tests = [
                Version("1.0.0-alpha"),
                Version("1.0.0-alpha.1"),
                Version("1.0.0-alpha.beta"),
                Version("1.0.0-beta"),
                Version("1.0.0-beta.2"),
                Version("1.0.0-beta.11"),
                Version("1.0.0-rc.1"),
                Version("1.0.0")
                ].map{ $0! }

            var v1: Version = tests.removeFirst()
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

    func testDescription() {
        XCTAssertEqual(Version(123,234,345, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011").description, "123.234.345-alpha.beta+1011")
    }

    func testFromString() {
        XCTAssertNil(Version(""))
        XCTAssertNil(Version("1"))
        XCTAssertNil(Version("1.2"))
        XCTAssertEqual(Version(1,2,3), Version("1.2.3"))
        XCTAssertNil(Version("1.2.3.4"))
        XCTAssertNil(Version("1.2.3.4.5"))

        XCTAssertNil(Version("a"))
        XCTAssertNil(Version("1.a"))
        XCTAssertNil(Version("a.2"))
        XCTAssertNil(Version("a.2.3"))
        XCTAssertNil(Version("1.a.3"))
        XCTAssertNil(Version("1.2.a"))

        XCTAssertNil(Version("-1.2.3"))
        XCTAssertNil(Version("1.-2.3"))
        XCTAssertNil(Version("1.2.-3"))
        XCTAssertNil(Version(".1.2.3"))
        XCTAssertNil(Version("v.1.2.3"))
        XCTAssertNil(Version("1.2..3"))
        XCTAssertNil(Version("v1.2.3"))

        XCTAssertEqual(Version(1,2,3), Version("01.002.0003"))

        XCTAssertEqual(Version(0,9,21), Version("0.9.21"))

        XCTAssertEqual(Version(0,9,21, prereleaseIdentifiers: ["alpha", "beta"], buildMetadataIdentifier: "1011"), Version("0.9.21-alpha.beta+1011"))

        XCTAssertEqual(Version(0,9,21, prereleaseIdentifiers: [], buildMetadataIdentifier: "1011"), Version("0.9.21+1011"))
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

    func testSuccessor() {
        let v1 = Version(1,0,0).successor()
        XCTAssertEqual(v1, Version(1,0,1))

        let v2 = Version(0,1,24).successor()
        XCTAssertEqual(v2, Version(0,1,25))

//FIXME: does not increase version
//        let v3 = Version(0,1,Int.max).successor()
//        XCTAssertNotEqual(v3, Version(0,1,0))

    }

    func testPredecessor() {
        let v1 = Version(1,1,1).predecessor()
        XCTAssertEqual(v1, Version(1,1,0))

        let v2 = Version(1,2,0).predecessor()
        XCTAssertEqual(v2, Version(1,1,Int.max))

        let v3 = Version(2,0,0).predecessor()
        XCTAssertEqual(v3, Version(1,Int.max,Int.max))

//FIXME. What is correct behavior when getting predecessor of Version(0,0,0)?
//        let v4 = Version(0,0,0).predecessor()
//        XCTAssertNotEqual(v4, Version(0,Int.max,Int.max))
    }

    static var allTests = [
        ("testEquality", testEquality),
        ("testNegativeValuesBecomeZero", testNegativeValuesBecomeZero),
        ("testHashable", testHashable),
        ("testComparable", testComparable),
        ("testDescription", testDescription),
        ("testFromString", testFromString),
        ("testOrder", testOrder),
        ("testRange", testRange),
        ("testSuccessor", testSuccessor),
        ("testPredecessor", testPredecessor),
        
    ]
}
