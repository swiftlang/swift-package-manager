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

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"1.0.0"), .empty)
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"1.0.1"), .exact("1.0.0"))
        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.1", "1.0.1"..<"2.0.0"]), .range("1.0.0"..<"2.0.0"))
    }

    func testUnionOfAdjacentExactVersions() {
        // {1.0.0} U {1.0.1} must contain both versions and must not collapse to empty.
        let pair = VersionSetSpecifier.exact("1.0.0").union(.exact("1.0.1"))
        XCTAssertNotEqual(pair, .empty)
        XCTAssertTrue(pair.contains("1.0.0"))
        XCTAssertTrue(pair.contains("1.0.1"))
        XCTAssertFalse(pair.contains("1.0.2"))
        XCTAssertEqual(pair, .range("1.0.0"..<"1.0.2"))

        // Order of operands must not matter.
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.1").union(.exact("1.0.0")), pair)

        // A chain of adjacent exacts keeps merging.
        let triple = pair.union(.exact("1.0.2"))
        XCTAssertTrue(triple.contains("1.0.0"))
        XCTAssertTrue(triple.contains("1.0.1"))
        XCTAssertTrue(triple.contains("1.0.2"))
        XCTAssertEqual(triple, .range("1.0.0"..<"1.0.3"))

        // The union's complement within a wider range excludes exactly those versions.
        let remainder = VersionSetSpecifier.range("1.0.0"..<"2.0.0").difference(pair)
        XCTAssertEqual(remainder, .range("1.0.2"..<"2.0.0"))
    }

    /// Unions that involve exact versions next to, inside, or apart from other ranges must keep exactly the
    /// versions of their operands, no matter how an exact version is represented internally. These cases pass
    /// both before and after the adjacent-exact-versions fix and guard against it changing their behavior.
    func testUnionOfExactVersionsWithOtherRanges() {
        let probes: [Version] = [
            "0.9.9", "1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9",
            "1.5.0", "1.9.9", "2.0.0", "2.0.1",
        ]

        func members(_ set: VersionSetSpecifier) -> [Version] {
            probes.filter { set.contains($0) }
        }

        // Asserts the union has exactly the expected members and that operand order doesn't matter.
        func assertUnion(
            _ lhs: VersionSetSpecifier,
            _ rhs: VersionSetSpecifier,
            members expected: [Version],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(members(lhs.union(rhs)), expected, "\(lhs) U \(rhs)", file: file, line: line)
            XCTAssertEqual(members(rhs.union(lhs)), expected, "\(rhs) U \(lhs)", file: file, line: line)
        }

        // Exact versions that are not adjacent stay separate.
        assertUnion(.exact("1.0.0"), .exact("1.0.5"), members: ["1.0.0", "1.0.5"])
        assertUnion(.exact("1.0.0"), .exact("1.0.2"), members: ["1.0.0", "1.0.2"])

        // Exact version directly below a range merges into it.
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.0").union(.range("1.0.1"..<"2.0.0")), .range("1.0.0"..<"2.0.0"))
        assertUnion(.exact("1.0.0"), .range("1.0.1"..<"2.0.0"), members: ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.5.0", "1.9.9"])

        // Exact version right at a range's exclusive upper bound extends it by exactly one patch.
        assertUnion(.exact("2.0.0"), .range("1.0.0"..<"2.0.0"), members: ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.5.0", "1.9.9", "2.0.0"])

        // Exact version already inside a range changes nothing.
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.1").union(.range("1.0.0"..<"2.0.0")), .range("1.0.0"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<"2.0.0").union(.exact("1.0.1")), .range("1.0.0"..<"2.0.0"))
        assertUnion(.exact("1.5.0"), .range("1.0.0"..<"2.0.0"), members: ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.5.0", "1.9.9"])

        // Exact version outside and away from a range stays separate.
        assertUnion(.exact("2.0.1"), .range("1.0.0"..<"1.0.5"), members: ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "2.0.1"])

        // Exact version attached to the end of one range of a disjoint list extends only that range.
        let disjoint = VersionSetSpecifier.ranges(["1.0.0"..<"1.0.5", "1.0.7"..<"1.0.9"])
        assertUnion(disjoint, .exact("1.0.5"), members: ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5", "1.0.7", "1.0.8"])

        // Exact version filling the one-patch gap between two ranges joins them.
        let gapped = VersionSetSpecifier.ranges(["1.0.0"..<"1.0.6", "1.0.7"..<"1.0.9"])
        XCTAssertEqual(gapped.union(.exact("1.0.6")), .range("1.0.0"..<"1.0.9"))
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.6").union(gapped), .range("1.0.0"..<"1.0.9"))

        // Union with the same exact version, empty, and any.
        assertUnion(.exact("1.0.1"), .exact("1.0.1"), members: ["1.0.1"])
        assertUnion(.exact("1.0.1"), .empty, members: ["1.0.1"])
        XCTAssertEqual(VersionSetSpecifier.exact("1.0.1").union(.any), .any)
    }

    /// Adjacent exact versions combined with further exacts and ranges.
    /// These only pass once `{1.0.0} U {1.0.1}` no longer collapses to the empty set.
    func testUnionOfAdjacentExactVersionsWithOtherRanges() {
        let pair = VersionSetSpecifier.exact("1.0.0").union(.exact("1.0.1"))

        // Adjacent exact versions followed by a distant exact version stay separate from it.
        for set in [pair.union(.exact("1.0.5")), VersionSetSpecifier.exact("1.0.5").union(pair)] {
            XCTAssertTrue(set.contains("1.0.0"))
            XCTAssertTrue(set.contains("1.0.1"))
            XCTAssertFalse(set.contains("1.0.2"))
            XCTAssertFalse(set.contains("1.0.4"))
            XCTAssertTrue(set.contains("1.0.5"))
            XCTAssertFalse(set.contains("1.0.6"))
        }

        // Adjacent exact versions merge with a range that starts right after them.
        XCTAssertEqual(pair.union(.range("1.0.2"..<"2.0.0")), .range("1.0.0"..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.2"..<"2.0.0").union(pair), .range("1.0.0"..<"2.0.0"))

        // ...but not with one that leaves a gap.
        let gapped = pair.union(.range("1.0.3"..<"2.0.0"))
        XCTAssertTrue(gapped.contains("1.0.1"))
        XCTAssertFalse(gapped.contains("1.0.2"))
        XCTAssertTrue(gapped.contains("1.0.3"))

        // Adjacent exact versions inside a range are absorbed by it.
        XCTAssertEqual(pair.union(.range("1.0.0"..<"2.0.0")), .range("1.0.0"..<"2.0.0"))

        // Removing a member of the pair leaves the other one.
        let withoutFirst = pair.difference(.exact("1.0.0"))
        XCTAssertFalse(withoutFirst.contains("1.0.0"))
        XCTAssertTrue(withoutFirst.contains("1.0.1"))
        let withoutSecond = pair.difference(.exact("1.0.1"))
        XCTAssertTrue(withoutSecond.contains("1.0.0"))
        XCTAssertFalse(withoutSecond.contains("1.0.1"))
        XCTAssertEqual(pair.difference(pair), .empty)
        XCTAssertEqual(pair.intersection(.exact("1.0.1")), .exact("1.0.1"))
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

    /// Subtracting the last version of a range leaves nothing above it. That remainder is `upper..<upper`,
    /// which is the empty set and must not turn into a member (e.g. `1.0.5` in `1.0.0..<1.0.5`).
    func testDifferenceOfExactVersionDoesNotLeaveEmptyRemainder() {
        // Removing the last version of a range shrinks it from above and does not add the upper bound back.
        let removedLast = VersionSetSpecifier.range("1.0.0"..<"1.0.5").difference(.exact("1.0.4"))
        XCTAssertEqual(removedLast, .range("1.0.0"..<"1.0.4"))
        for member in ["1.0.0", "1.0.1", "1.0.2", "1.0.3"] as [Version] {
            XCTAssertTrue(removedLast.contains(member), "\(member) should be in \(removedLast)")
        }
        for nonMember in ["0.9.9", "1.0.4", "1.0.5", "1.0.6"] as [Version] {
            XCTAssertFalse(removedLast.contains(nonMember), "\(nonMember) should not be in \(removedLast)")
        }

        // Two-version range minus its second version leaves exactly its first version.
        let single = VersionSetSpecifier.range("1.0.0"..<"1.0.2").difference(.exact("1.0.1"))
        XCTAssertEqual(single, .exact("1.0.0"))
        XCTAssertTrue(single.contains("1.0.0"))
        XCTAssertFalse(single.contains("1.0.1"))
        XCTAssertFalse(single.contains("1.0.2"))

        // A pair of adjacent exact versions minus either member leaves exactly the other one.
        let pair = VersionSetSpecifier.exact("1.0.0").union(.exact("1.0.1"))
        XCTAssertEqual(pair.difference(.exact("1.0.1")), .exact("1.0.0"))
        XCTAssertEqual(pair.difference(.exact("1.0.0")), .exact("1.0.1"))

        // The disjoint-ranges case already guards the empty remainder; keep it that way.
        let disjoint = VersionSetSpecifier.ranges(["1.0.0"..<"1.0.5", "1.0.7"..<"1.0.9"]).difference(.exact("1.0.4"))
        XCTAssertTrue(disjoint.contains("1.0.3"))
        XCTAssertFalse(disjoint.contains("1.0.4"))
        XCTAssertFalse(disjoint.contains("1.0.5"))
        XCTAssertTrue(disjoint.contains("1.0.7"))

        // A leftover empty remainder must not be turned into a member by a later union
        // with an exact version that sits right after it.
        let laundered = removedLast.union(.exact("1.0.6"))
        XCTAssertTrue(laundered.contains("1.0.3"))
        XCTAssertFalse(laundered.contains("1.0.4"))
        XCTAssertFalse(laundered.contains("1.0.5"))
        XCTAssertTrue(laundered.contains("1.0.6"))
        let launderedFromRemainder = VersionSetSpecifier.range("1.0.0"..<"1.0.5").difference(.exact("1.0.4")).union(.exact("1.0.5"))
        XCTAssertEqual(launderedFromRemainder, .range("1.0.0"..<"1.0.4").union(.exact("1.0.5")))
        XCTAssertFalse(launderedFromRemainder.contains("1.0.4"))
        XCTAssertTrue(launderedFromRemainder.contains("1.0.5"))
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
