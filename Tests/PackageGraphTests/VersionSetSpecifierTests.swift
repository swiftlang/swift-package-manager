//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import TSCUtility
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
        XCTAssertEqual(VersionSetSpecifier.range("2.0.0"..<"2.0.1").difference(.exact("2.0.0")), .empty)

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


        XCTAssertEqual(VersionSetSpecifier.exact("1.0.0-beta").difference(.exact("1.0.0-beta")), .empty)
        XCTAssertEqual(VersionSetSpecifier.exact("2.0.0-beta").difference(.exact("1.0.0")), .exact("2.0.0-beta"))
        XCTAssertEqual(VersionSetSpecifier.exact("2.0.0-beta").difference(.exact("1.0.0-beta")), .exact("2.0.0-beta"))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"1.0.0-beta").difference(.range("1.0.0-beta"..<"1.0.0-beta")), .empty)
        XCTAssertEqual(VersionSetSpecifier.range("2.0.0-beta"..<"2.0.0-beta").difference(.range("1.0.0"..<"2.0.0")), .range("2.0.0-beta"..<"2.0.0-beta"))
        XCTAssertEqual(VersionSetSpecifier.range("2.0.0-beta"..<"2.0.0-beta").difference(.range("1.0.0-beta"..<"2.0.0")), .range("2.0.0-beta"..<"2.0.0-beta"))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("2.0.0")), .range("1.0.0-beta"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta")), .range("1.0.0-beta.0"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta.5")), .ranges(["1.0.0-beta"..<"1.0.0-beta.5", "1.0.0-beta.5.0"..<"2.0.0"]))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.range("1.0.0-beta.3" ..< "2.0.0")), .range("1.0.0-beta"..<"1.0.0-beta.3"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta.5"..<"1.0.0-beta.30").difference(.range("1.0.0-beta.10" ..< "2.0.0")), .range("1.0.0-beta.5"..<"1.0.0-beta.10"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"1.0.0-beta.30").difference(.range("1.0.0-beta.3" ..< "1.0.0-beta.10")), .ranges(["1.0.0-beta"..<"1.0.0-beta.3", "1.0.0-beta.10"..<"1.0.0-beta.30"]))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-alpha"..<"2.0.0").difference(.range("1.0.0-beta" ..< "2.0.0")), .range("1.0.0-alpha"..<"1.0.0-beta"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.range("1.0.0-alpha" ..< "2.0.0")), .empty)
    }

    func testEquality() {
        // Basic cases.
        XCTAssertTrue(VersionSetSpecifier.any == VersionSetSpecifier.any)
        XCTAssertTrue(VersionSetSpecifier.empty == VersionSetSpecifier.empty)
        XCTAssertTrue(VersionSetSpecifier.range("1.0.0"..<"5.0.0") == VersionSetSpecifier.range("1.0.0"..<"5.0.0"))
        XCTAssertTrue(VersionSetSpecifier.exact("1.2.3") == VersionSetSpecifier.exact("1.2.3"))
        XCTAssertTrue(VersionSetSpecifier.ranges(["3.2.0"..<"3.2.1", "3.2.3"..<"4.0.0"]) == VersionSetSpecifier.ranges(["3.2.0"..<"3.2.1", "3.2.3"..<"4.0.0"]))

        // Empty is equivalent to an empty list of ranges or if the list contains one range where the lower bound equals the upper bound./
        XCTAssertTrue(VersionSetSpecifier.empty == VersionSetSpecifier.ranges([]))
        XCTAssertTrue(VersionSetSpecifier.ranges([]) == VersionSetSpecifier.empty)
        XCTAssertTrue(VersionSetSpecifier.empty == VersionSetSpecifier.ranges(["2.0.0"..<"2.0.0"]))
        XCTAssertTrue(VersionSetSpecifier.ranges(["2.0.0"..<"2.0.0"]) == VersionSetSpecifier.empty)

        // Empty is equivalent to a range where the lower bound equals the upper bound.
        XCTAssertTrue(VersionSetSpecifier.empty == VersionSetSpecifier.range("2.0.0"..<"2.0.0"))
        XCTAssertTrue(VersionSetSpecifier.range("2.0.0"..<"2.0.0") == VersionSetSpecifier.empty)

        // Exact is equal to a range that spans a single patch.
        XCTAssertTrue(VersionSetSpecifier.exact("2.0.1") == VersionSetSpecifier.range("2.0.1"..<"2.0.2"))
        XCTAssertTrue(VersionSetSpecifier.range("2.0.1"..<"2.0.2") == VersionSetSpecifier.exact("2.0.1"))

        // Exact is also equal to a list of ranges with one entry that spans a single patch.
        XCTAssertTrue(VersionSetSpecifier.exact("2.0.1") == VersionSetSpecifier.ranges(["2.0.1"..<"2.0.2"]))
        XCTAssertTrue(VersionSetSpecifier.ranges(["2.0.1"..<"2.0.2"]) == VersionSetSpecifier.exact("2.0.1"))

        // A range is equal to a list of ranges with that one range.
        XCTAssertTrue(VersionSetSpecifier.range("2.0.1"..<"2.0.2") == VersionSetSpecifier.ranges(["2.0.1"..<"2.0.2"]))
        XCTAssertTrue(VersionSetSpecifier.ranges(["2.0.1"..<"2.0.2"]) == VersionSetSpecifier.range("2.0.1"..<"2.0.2"))
    }

    func testPrereleases() {
        XCTAssertFalse(VersionSetSpecifier.any.supportsPrereleases)
        XCTAssertFalse(VersionSetSpecifier.empty.supportsPrereleases)
        XCTAssertFalse(VersionSetSpecifier.exact("0.0.1").supportsPrereleases)

        XCTAssertTrue(VersionSetSpecifier.exact("0.0.1-latest").supportsPrereleases)
        XCTAssertTrue(VersionSetSpecifier.range("0.0.1-latest" ..< "2.0.0").supportsPrereleases)
        XCTAssertTrue(VersionSetSpecifier.range("0.0.1" ..< "2.0.0-latest").supportsPrereleases)

        XCTAssertTrue(VersionSetSpecifier.ranges([
            "0.0.1" ..< "0.0.2",
            "0.0.1" ..< "2.0.0-latest",
        ]).supportsPrereleases)

        XCTAssertTrue(VersionSetSpecifier.ranges([
            "0.0.1-latest" ..< "0.0.2",
            "0.0.1" ..< "2.0.0",
        ]).supportsPrereleases)

        XCTAssertFalse(VersionSetSpecifier.ranges([
            "0.0.1" ..< "0.0.2",
            "0.0.1" ..< "2.0.0",
        ]).supportsPrereleases)
    }
}
