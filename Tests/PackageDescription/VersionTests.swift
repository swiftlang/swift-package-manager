/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import PackageDescription
import func libc.rand
import XCTest

class VersionTests: XCTestCase {

    func testEquality() {
        func test(@autoclosure v: () -> Version) {
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

    func testSort() {
        let transformed = "0.9.1 0.9.10 0.9.11 0.9.11.1 0.9.12 0.9.13 0.9.13.1 0.9.13.2 0.9.14 0.9.14.1 0.9.14.2 0.9.14.3 0.9.15 0.9.15.1 0.9.15.2 0.9.15.3 0.9.16 0.9.16.1 0.9.16.2 0.9.16.3 0.9.16.4 0.9.16.5 0.9.16.6 0.9.17 0.9.17.1 0.9.18 0.9.19 0.9.2 0.9.20 0.9.21 0.9.3 0.9.4 0.9.5 0.9.6 0.9.7 0.9.7.1 0.9.7.2 0.9.7.3 0.9.7.4 0.9.7.5 0.9.8 0.9.8.1 0.9.9 1.0 1.0.1 1.0.2 1.0.3 1.1 1.2 1.2.1 1.2.2 1.2.3 1.2.4 1.2.5 1.3.0 1.3.1 1.3.2 1.4.0 1.4.1 1.4.2 1.4.3 1.5.0 1.5.1 1.5.2 1.5.3 1.6.0 2.0.0 2.0.1 2.0.2 2.0.3 2.0.4 2.0.5 2.0.6 2.1.0 2.1.1 2.1.2 2.1.3 2.2.0 2.2.1 2.2.2 ".characters.split(separator: " ").flatMap(Version.init).shuffle().sorted()

        let expected = [
            Version(0,9,1),
            Version(0,9,2),
            Version(0,9,3),
            Version(0,9,4),
            Version(0,9,5),
            Version(0,9,6),
            Version(0,9,7),
            Version(0,9,8),
            Version(0,9,9),
            Version(0,9,10),
            Version(0,9,11),
            Version(0,9,12),
            Version(0,9,13),
            Version(0,9,14),
            Version(0,9,15),
            Version(0,9,16),
            Version(0,9,17),
            Version(0,9,18),
            Version(0,9,19),
            Version(0,9,20),
            Version(0,9,21),
            Version(1,0,1),
            Version(1,0,2),
            Version(1,0,3),
            Version(1,2,1),
            Version(1,2,2),
            Version(1,2,3),
            Version(1,2,4),
            Version(1,2,5),
            Version(1,3,0),
            Version(1,3,1),
            Version(1,3,2),
            Version(1,4,0),
            Version(1,4,1),
            Version(1,4,2),
            Version(1,4,3),
            Version(1,5,0),
            Version(1,5,1),
            Version(1,5,2),
            Version(1,5,3),
            Version(1,6,0),
            Version(2,0,0),
            Version(2,0,1),
            Version(2,0,2),
            Version(2,0,3),
            Version(2,0,4),
            Version(2,0,5),
            Version(2,0,6),
            Version(2,1,0),
            Version(2,1,1),
            Version(2,1,2),
            Version(2,1,3),
            Version(2,2,0),
            Version(2,2,1),
            Version(2,2,2)
        ]

        XCTAssertEqual(transformed, expected)
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

}


extension Array {
    func shuffle() -> Array {
        switch count {
        case 0, 1:
            return self;
        default:
            var out = self;
            for i in (0..<count).reversed() {
                let j = Int(rand()) % (i + 1)
                (out[i], out[j]) = (out[j], out[i])
            }
            return out
        }
    }
}


extension VersionTests {
    static var allTests : [(String, VersionTests -> () throws -> Void)] {
        return [
            ("testEquality", testEquality),
            ("testNegativeValuesBecomeZero", testNegativeValuesBecomeZero),
            ("testComparable", testComparable),
            ("testDescription", testDescription),
            ("testFromString", testFromString),
            ("testSort", testSort),
            ("testRange", testRange),
            ("testSuccessor", testSuccessor),
            ("testPredecessor", testPredecessor),
            
        ]
    }
}
