/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

import PackageGraph

final class VersionSetSpecifierTests: XCTestCase {
    func testUnion() {
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.1"]), .exact("1.0.0"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5"]), .range("1.0.0"..<"1.0.5"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.6", "1.0.5"..<"1.0.9"]), .range("1.0.0"..<"1.0.9"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.5"..<"1.0.9"]), .range("1.0.0"..<"1.0.9"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.5"..<"1.0.9", "1.0.0"..<"1.0.5"]), .range("1.0.0"..<"1.0.9"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.5"..<"1.0.9", "1.0.11"..<"1.0.15"]), .ranges(["1.0.0"..<"1.0.9", "1.0.11"..<"1.0.15"]))
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.0").union(.exact("1.0.0")), .exact("1.0.0"))

        let ranges1 = VersionSetSpecifier.union(from: ["1.0.0"..<"1.1.0", "1.1.1"..<"2.0.0"])
        XCTAssertEqual(ranges1.union(.exact("1.1.0")), .range("1.0.0"..<"2.0.0"))

        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.0", "1.0.1"..<"2.0.0"]), .range("1.0.0"..<"2.0.0"))
    }

    func testIntersection() {
        let ranges = VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.6"..<"1.0.10"])
        XCTAssertEqual(ranges.intersection(.range("1.0.1"..<"1.0.8")), .ranges(["1.0.1"..<"1.0.5", "1.0.6"..<"1.0.8"]))

        let ranges1 = VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.6"..<"1.0.10"])
        let ranges2 = VersionSetSpecifier.union(from: ["1.0.1"..<"1.0.3", "1.0.8"..<"1.0.9"])
        XCTAssertEqual(ranges1.intersection(ranges2), .ranges(["1.0.1"..<"1.0.3", "1.0.8"..<"1.0.9"]))
    }

    func testDifference() {
        do {
            let v1: VersionSetSpecifier = .exact("1.0.0")
            let v2: VersionSetSpecifier = .exact("2.0.0")
            XCTAssertEqual(v1.difference(v1), .empty)
            XCTAssertEqual(v2.difference(v1), v2)
        }

        do {
            let v1: VersionSetSpecifier = .range("1.0.0"..<"1.0.0")
            let v2: VersionSetSpecifier = .range("2.0.0"..<"2.0.0")
            XCTAssertEqual(v1.difference(v1), .empty)
            XCTAssertEqual(v2.difference(v1), v2)
        }

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(.exact("2.0.0")), .range("1.0.0"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(.exact("1.0.0")), .range("1.0.1"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(.exact("1.5.0")), .ranges(["1.0.0"..<"1.5.0", "1.5.1"..<"2.0.0"]))
        XCTAssertEqual(VersionSetSpecifier.range("2.0.0"..<"2.0.0").difference(.exact("2.0.0")), .empty)

        XCTAssertEqual(VersionSetSpecifier.exact("1.0.0").difference(.range("1.0.0"..<"2.0.0")), .empty)
        XCTAssertEqual(VersionSetSpecifier.exact("3.0.0").difference(.range("1.0.0"..<"2.0.0")), .exact("3.0.0"))

        XCTAssertEqual(VersionSetSpecifier.exact("3.0.0").difference(.any), .empty)

        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"]).difference(.exact("2.0.0")), .ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"]))
        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"]).difference(.exact("1.0.0")), .ranges(["1.0.1"..<"2.0.0", "3.0.0"..<"4.0.0"]))
        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"]).difference(.exact("3.5.0")), .ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"3.5.0", "3.5.1"..<"4.0.0"]))

        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"1.0.0", "3.0.0"..<"4.0.0"]).difference(.exact("1.0.0")), .range("3.0.0"..<"4.0.0"))

        XCTAssertEqual(VersionSetSpecifier.exact("1.5.0").difference(.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"])), .empty)
        XCTAssertEqual(VersionSetSpecifier.exact("2.0.0").difference(.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"])), .exact("2.0.0"))

        do {
            let v1: VersionSetSpecifier = .range("1.0.0"..<"2.0.0")
            let v1_5: VersionSetSpecifier = .range("1.5.0"..<"2.0.0")
            let v1_49: VersionSetSpecifier = .range("1.4.9"..<"2.0.0")

            XCTAssertEqual(v1.difference(v1), .empty)
            XCTAssertEqual(v1.difference(.range("2.0.0"..<"2.0.0")), v1)
            XCTAssertEqual(v1.difference(v1_5), .range("1.0.0"..<"1.5.0"))
            XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(.range("1.1.0"..<"1.5.0")), .ranges(["1.0.0"..<"1.1.0", "1.5.0"..<"2.0.0"]))
            XCTAssertEqual(v1_49.difference(v1_5), .range("1.4.9"..<"1.5.0"))
            XCTAssertEqual(v1_5.difference(v1_49), .empty)
        }

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"5.0.0").difference(.ranges(["1.0.0"..<"2.0.0", "3.0.0"..<"4.0.0"])), .ranges(["2.0.0"..<"3.0.0", "4.0.0"..<"5.0.0"]))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(.range("1.0.0"..<"1.8.0")), .range("1.8.0"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"5.0.0").difference(.ranges(["1.0.0"..<"2.0.0", "2.0.1"..<"5.0.0"])), .exact("2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.ranges(["3.2.1"..<"3.2.4", "3.2.5"..<"4.0.0"]).difference(.ranges(["3.2.1"..<"3.2.3", "3.2.3"..<"4.0.0"])), .exact("3.2.3"))

        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"2.0.0", "2.0.1"..<"5.0.0"]).difference(.ranges(["1.0.0"..<"2.0.0", "2.0.1"..<"5.0.0"])), .empty)
        XCTAssertEqual(VersionSetSpecifier.ranges(["0.0.0"..<"0.9.1", "1.0.0"..<"2.0.0", "2.0.1"..<"5.0.0"]).difference(.ranges(["1.0.0"..<"1.4.0", "2.4.1"..<"4.0.0"])), .ranges(["0.0.0"..<"0.9.1", "1.4.0"..<"2.0.0", "2.0.1"..<"2.4.1", "4.0.0"..<"5.0.0"]))

        XCTAssertEqual(VersionSetSpecifier.ranges(["1.0.0"..<"2.0.0", "2.0.1"..<"5.0.0"]).difference(.range("1.0.0"..<"2.0.0")), .range("2.0.1"..<"5.0.0"))
        XCTAssertEqual(VersionSetSpecifier.ranges(["3.2.0"..<"3.2.3", "3.2.4"..<"4.0.0"]).difference(.exact("3.2.2")), .ranges(["3.2.0"..<"3.2.2", "3.2.4"..<"4.0.0"]))
        XCTAssertEqual(VersionSetSpecifier.ranges(["3.2.0"..<"3.2.1", "3.2.3"..<"4.0.0"]).difference(.exact("3.2.0")), .range("3.2.3"..<"4.0.0"))
    }
}
