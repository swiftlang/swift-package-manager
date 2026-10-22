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

@testable import PackageGraph

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

        XCTAssertEqual(VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.0", "1.0.1"..<"2.0.0"]), .range("1.0.1"..<"2.0.0"))
    }

    func testIntersection() {
        let ranges = VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.6"..<"1.0.10"])
        XCTAssertEqual(ranges.intersection(.range("1.0.1"..<"1.0.8")), .ranges(["1.0.1"..<"1.0.5", "1.0.6"..<"1.0.8"]))

        let ranges1 = VersionSetSpecifier.union(from: ["1.0.0"..<"1.0.5", "1.0.6"..<"1.0.10"])
        let ranges2 = VersionSetSpecifier.union(from: ["1.0.1"..<"1.0.3", "1.0.8"..<"1.0.9"])
        XCTAssertEqual(ranges1.intersection(ranges2), .ranges(["1.0.1"..<"1.0.3", "1.0.8"..<"1.0.9"]))
    }

    func testIntersectionInfersPrereleaseSupportFromEitherOperand() {
        // A prerelease bound is an opt-in that `Range.contains(version:)`
        // applies to the whole range, and intersecting clamps bounds ordinally,
        // so the opt-in survives into the result even though the release-only
        // operand does not contain those prereleases on its own. This widening
        // is deliberate: it is how a release-only requirement inherited from a
        // transitive dependency avoids vetoing the prereleases that the root
        // package asked for. `PubGrubBacktrackTests` covers the resolver-level
        // behaviour in `testPrereleaseVersionSelection` and
        // `testPrereleaseInferenceThroughDependencies`.
        let releasesOnly = VersionSetSpecifier.range("1.0.0"..<"2.0.0")
        let prereleasesAllowed = VersionSetSpecifier.range("0.9.0"..<"2.0.0-alpha")
        let result = releasesOnly.intersection(prereleasesAllowed)

        XCTAssertEqual(result, .range("1.0.0"..<"2.0.0-alpha"))
        XCTAssertTrue(result.contains("1.0.1-alpha"))
        XCTAssertTrue(result.contains("1.0.1"))
        // Clamping still applies on both ends.
        XCTAssertFalse(result.contains("0.9.9"))
        XCTAssertFalse(result.contains("2.0.0"))
    }

    func testIntersectionDoesNotInferPrereleaseSupportFromAnExactRequirement() {
        // An exact requirement names a single version, so it is intersected by
        // membership instead of by clamping bounds. Pinning a prerelease must
        // therefore not opt a release-only range into prereleases, which is
        // what `PubGrubBacktrackTests.testPrereleaseExactRequirement` asserts.
        let releaseRange = VersionSetSpecifier.range("1.0.4"..<"2.0.0")
        let exactPrerelease = VersionSetSpecifier.exact("1.0.6-prerelease-1")

        XCTAssertFalse(releaseRange.contains("1.0.6-prerelease-1"))
        XCTAssertEqual(releaseRange.intersection(exactPrerelease), .empty)
        XCTAssertEqual(exactPrerelease.intersection(releaseRange), .empty)

        // A range that opts into prereleases still admits the pinned version.
        let prereleaseRange = VersionSetSpecifier.range("1.0.5"..<"1.0.6-prerelease-2")
        XCTAssertEqual(prereleaseRange.intersection(exactPrerelease), exactPrerelease)
        XCTAssertEqual(exactPrerelease.intersection(prereleaseRange), exactPrerelease)
    }

    func testUnionPreservesExactMembersWithoutEmptyRanges() {
        let mixed = VersionSetSpecifier.exact("1.2.0").union(.range("1.3.0"..<"1.5.0"))
        XCTAssertTrue(mixed.contains("1.2.0"))
        XCTAssertTrue(mixed.contains("1.3.0"))
        XCTAssertFalse(mixed.contains("1.2.1"))
        XCTAssertEqual(mixed.description, "{1.2.0, 1.3.0..<1.5.0}")

        guard case .ranges(let ranges) = mixed else {
            return XCTFail("expected a disjoint version set, got \(mixed)")
        }
        XCTAssertTrue(ranges.allSatisfy { $0.lowerBound < $0.upperBound })

        let adjacent = VersionSetSpecifier.exact("1.0.2").union(.exact("1.0.3"))
        XCTAssertTrue(adjacent.contains("1.0.2"))
        XCTAssertTrue(adjacent.contains("1.0.3"))

        let broad = VersionSetSpecifier.range("1.0.0"..<"2.0.0")
        XCTAssertEqual(broad.union(.exact("1.2.0")), broad)
    }

    func testIntersectionIsReflexiveForMixedExactAndRangeSets() {
        // Intersection must be reflexive (x ∩ x == x). Dropping the exact
        // member of a mixed requirement breaks the intersection-based subset
        // checks in `Term.relation(with:)`, which makes
        // `PartialSolution.satisfier(for:)` fail to find a satisfier for a term
        // that is identical to the accumulated assignments.
        let mixed = VersionSetSpecifier.exact("1.2.0").union(.range("1.3.0"..<"1.5.0"))
        XCTAssertEqual(mixed.intersection(mixed), mixed)
    }

    func testIntersectionAgreesWithContainsForExactMembers() {
        // A version contained in both operands must survive the intersection.
        let mixed = VersionSetSpecifier.exact("1.2.0").union(.range("1.3.0"..<"1.5.0"))
        let broad = VersionSetSpecifier.range("1.0.0"..<"2.0.0")

        XCTAssertTrue(mixed.contains("1.2.0"))
        XCTAssertTrue(broad.contains("1.2.0"))

        let result = mixed.intersection(broad)
        XCTAssertTrue(
            result.contains("1.2.0"),
            "1.2.0 is in both operands but was dropped by intersection: \(result)"
        )
    }

    func testRangesIntersectionPreservesSharedExactPoint() {
        let lhs = VersionSetSpecifier.ranges(["1.2.0"..<"1.2.1", "1.3.0"..<"1.5.0"])
        let rhs = VersionSetSpecifier.ranges(["1.2.0"..<"1.2.1", "1.6.0"..<"1.7.0"])
        let result = lhs.intersection(rhs)
        XCTAssertNotEqual(result, .empty)
        XCTAssertEqual(result, .exact("1.2.0"))
        XCTAssertTrue(result.contains("1.2.0"), "shared exact point dropped: \(result)")
    }

    func testEmptyRangeHasEmptySetSemantics() {
        let emptyRange = VersionSetSpecifier.range("1.2.0"..<"1.2.0")
        XCTAssertEqual(emptyRange, .empty)
        XCTAssertFalse(emptyRange.contains("1.2.0"))
        XCTAssertEqual(emptyRange.union(.exact("1.3.0")), .exact("1.3.0"))
        XCTAssertEqual(emptyRange.intersection(.exact("1.2.0")), .empty)
        XCTAssertEqual(emptyRange.difference(.exact("1.2.0")), .empty)
    }

    func testSemanticallyEmptyPrereleaseRangeIsEmpty() {
        let emptyRange = VersionSetSpecifier.range("1.0.0-alpha"..<"1.0.0")

        XCTAssertEqual(emptyRange, .empty)
        XCTAssertEqual(emptyRange.hashValue, VersionSetSpecifier.empty.hashValue)
        XCTAssertFalse(emptyRange.contains("1.0.0-alpha"))
        XCTAssertFalse(emptyRange.supportsPrereleases)
        XCTAssertEqual(emptyRange.intersection(emptyRange), .empty)
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
        XCTAssertEqual(VersionSetSpecifier.ranges(["3.2.1"..<"3.2.4", "3.2.5"..<"4.0.0"]).difference(.ranges(["3.2.1"..<"3.2.3", "3.2.3"..<"4.0.0"])), .empty)

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
        // The remainder resumes at the smallest prerelease after the removed
        // one, `<removed>.<Int.min>`, so `1.0.0-beta.-1` is kept.
        let afterBeta = Version(1, 0, 0, prereleaseIdentifiers: ["beta", String(Int.min)])
        let afterBeta5 = Version(1, 0, 0, prereleaseIdentifiers: ["beta", "5", String(Int.min)])
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta")), .range(afterBeta..<"2.0.0"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta.5")), .ranges(["1.0.0-beta"..<"1.0.0-beta.5", afterBeta5..<"2.0.0"]))
        XCTAssertTrue(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta")).contains("1.0.0-beta.-1"))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.range("1.0.0-beta.3" ..< "2.0.0")), .range("1.0.0-beta"..<"1.0.0-beta.3"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta.5"..<"1.0.0-beta.30").difference(.range("1.0.0-beta.10" ..< "2.0.0")), .range("1.0.0-beta.5"..<"1.0.0-beta.10"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"1.0.0-beta.30").difference(.range("1.0.0-beta.3" ..< "1.0.0-beta.10")), .ranges(["1.0.0-beta"..<"1.0.0-beta.3", "1.0.0-beta.10"..<"1.0.0-beta.30"]))

        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-alpha"..<"2.0.0").difference(.range("1.0.0-beta" ..< "2.0.0")), .range("1.0.0-alpha"..<"1.0.0-beta"))
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.range("1.0.0-alpha" ..< "2.0.0")), .empty)
    }

    func testRangesDifferenceHandlesShiftedOverlap() {
        let lhs = VersionSetSpecifier.ranges([
            "1.0.0"..<"1.0.2",
            "1.0.3"..<"1.0.4",
        ])
        let rhs = VersionSetSpecifier.range("1.0.1"..<"1.0.3")

        XCTAssertEqual(
            lhs.difference(rhs),
            .ranges(["1.0.0"..<"1.0.1", "1.0.3"..<"1.0.4"])
        )
    }

    func testPrereleaseRangeDifferencePreservesRepresentablePrereleases() {
        let range = VersionSetSpecifier.range("1.0.0-alpha"..<"2.0.0")
        let result = range.difference(.exact("1.5.0"))

        XCTAssertTrue(result.contains("1.4.0-beta"))
        XCTAssertFalse(result.contains("1.5.0"))
        XCTAssertTrue(result.contains("1.5.1-beta"))

        let boundaryResult = range.difference(.exact("1.0.0"))
        XCTAssertFalse(boundaryResult.contains("1.0.0"))
        XCTAssertTrue(boundaryResult.contains("1.0.1-alpha"))

        let stableLowerBound = VersionSetSpecifier.range("0.9.0"..<"2.0.0-alpha")
        let stableLowerBoundResult = stableLowerBound.difference(.exact("1.5.0"))
        XCTAssertTrue(stableLowerBoundResult.contains("1.0.0-alpha"))
        XCTAssertTrue(stableLowerBoundResult.contains("1.0.1-alpha"))
        XCTAssertFalse(stableLowerBoundResult.contains("1.5.0"))
        XCTAssertTrue(stableLowerBoundResult.contains("1.5.1-alpha"))
    }

    func testPrereleaseRangeIntersectionMembershipLaws() {
        let versions: [Version] = [
            "0.9.0", "1.0.0-alpha", "1.0.0", "1.0.1-alpha", "1.0.1",
            "1.5.0-beta", "1.5.0", "1.5.1-alpha", "1.9.0", "2.0.0-alpha", "2.0.0",
        ]
        let sets: [VersionSetSpecifier] = [
            .empty,
            .exact("1.0.0-alpha"),
            .exact("1.5.0"),
            .range("1.0.0"..<"2.0.0"),
            .range("0.9.0"..<"2.0.0-alpha"),
            .range("1.0.0-alpha"..<"2.0.0"),
            .range("1.0.0-alpha"..<"1.0.0-beta"),
            .exact("1.0.0-alpha").union(.range("1.0.0"..<"2.0.0")),
        ]

        for lhs in sets {
            for rhs in sets {
                let intersection = lhs.intersection(rhs)
                for version in versions {
                    // Intersection is an ordinal approximation that can over-
                    // or under-approximate prereleases in general
                    // (`1.0.0-alpha..<2.0.0 ∩ 1.5.0..<3.0.0-beta` is
                    // `1.5.0..<2.0.0`, which drops `1.6.0-alpha`), but for
                    // these sampled shapes nothing both operands contain is
                    // dropped.
                    if lhs.contains(version), rhs.contains(version) {
                        XCTAssertTrue(
                            intersection.contains(version),
                            "intersection dropped \(version) shared by \(lhs) and \(rhs)"
                        )
                    }

                    // For releases the intersection is exact. Prereleases are
                    // deliberately over-approximated, because a prerelease
                    // bound on either operand opts the whole result in; see
                    // `testIntersectionInfersPrereleaseSupportFromEitherOperand`.
                    if version.prereleaseIdentifiers.isEmpty {
                        XCTAssertEqual(
                            intersection.contains(version),
                            lhs.contains(version) && rhs.contains(version),
                            "intersection membership mismatch for \(lhs), \(rhs), and \(version)"
                        )
                    }

                    // Even the over-approximation stays within the ordinal
                    // bounds of both operands.
                    if intersection.contains(version) {
                        XCTAssertTrue(
                            lhs.ordinallyContains(version) && rhs.ordinallyContains(version),
                            "intersection admitted \(version) outside \(lhs) or \(rhs)"
                        )
                    }
                }
            }
        }
    }

    func testReleaseOnlyRangeDifferenceDoesNotAdmitPrereleases() {
        // Removing prereleases from a range that admits none must not hand a
        // prerelease bound to the remaining pieces, which would opt them into
        // prereleases that the original range never contained.
        let releasesOnly = VersionSetSpecifier.range("1.0.0"..<"2.0.0")
        XCTAssertFalse(releasesOnly.contains("1.4.0-beta"))

        // A prerelease-bounded range that contains no release removes nothing.
        let prereleasesOnly = VersionSetSpecifier.range("1.5.0-alpha"..<"1.5.0-beta")
        let withoutPrereleasesOnly = releasesOnly.difference(prereleasesOnly)
        XCTAssertEqual(withoutPrereleasesOnly, releasesOnly)
        XCTAssertFalse(withoutPrereleasesOnly.contains("1.4.0-beta"))
        XCTAssertFalse(withoutPrereleasesOnly.supportsPrereleases)

        // Only the releases of a prerelease-bounded range are removed.
        let prereleaseRange = VersionSetSpecifier.range("1.4.0-alpha"..<"1.6.0-beta")
        let withoutPrereleaseRange = releasesOnly.difference(prereleaseRange)
        XCTAssertEqual(withoutPrereleaseRange, .ranges(["1.0.0"..<"1.4.0", "1.6.0"..<"2.0.0"]))
        XCTAssertFalse(withoutPrereleaseRange.supportsPrereleases)
        XCTAssertTrue(withoutPrereleaseRange.contains("1.3.0"))
        XCTAssertFalse(withoutPrereleaseRange.contains("1.4.0"))
        XCTAssertFalse(withoutPrereleaseRange.contains("1.5.0"))
        XCTAssertTrue(withoutPrereleaseRange.contains("1.6.0"))
        XCTAssertFalse(withoutPrereleaseRange.contains("1.6.0-alpha"))
        XCTAssertFalse(withoutPrereleaseRange.contains("1.7.0-alpha"))
    }

    func testPrereleaseRangeDifferenceDoesNotReadmitExcludedVersions() {
        let versions: [Version] = [
            "0.9.0", "1.0.0-alpha", "1.0.0", "1.0.1-alpha", "1.0.1-beta", "1.0.1",
            "1.4.0-beta", "1.4.0", "1.5.0-alpha", "1.5.0-alpha.0", "1.5.0-alpha.0.0",
            "1.5.0-beta", "1.5.0", "1.5.1-alpha", "1.6.0-alpha", "1.6.0", "1.7.0-alpha",
            "1.9.0", "2.0.0-alpha", "2.0.0", "2.5.0",
        ]
        let sets: [VersionSetSpecifier] = [
            .empty,
            .exact("1.0.0-alpha"),
            .exact("1.5.0"),
            .range("1.0.0"..<"2.0.0"),
            .range("0.9.0"..<"2.0.0-alpha"),
            .range("1.0.0-alpha"..<"2.0.0"),
            .range("1.0.0-alpha"..<"1.0.0-beta"),
            .range("1.4.0-alpha"..<"1.6.0-beta"),
            .exact("1.0.0-alpha").union(.range("1.0.0"..<"2.0.0")),
            .exact("1.5.0-alpha").union(.exact("1.5.0-alpha.0")),
            .ranges(["1.0.0-alpha"..<"1.0.1", "2.0.0"..<"3.0.0"]),
            .range("1.0.1-beta"..<"2.0.0-alpha"),
        ]

        for (lhsIndex, lhs) in sets.enumerated() {
            for (rhsIndex, rhs) in sets.enumerated() {
                for version in versions {
                    guard lhs.difference(rhs).contains(version) else { continue }
                    XCTAssertTrue(
                        lhs.contains(version),
                        "difference admitted \(version) outside [\(lhsIndex)] \(lhs) minus [\(rhsIndex)] \(rhs)"
                    )
                    XCTAssertFalse(
                        rhs.contains(version),
                        "difference readmitted \(version) for [\(lhsIndex)] \(lhs) minus [\(rhsIndex)] \(rhs)"
                    )
                }
            }
        }
    }

    func testDifferenceAtPrereleaseOfReleaseUpperBoundRemovesNothing() {
        // `1.0.0-alpha..<1.0.1` admits no `1.0.1` prerelease, so removing a
        // range that starts at one must not end the remaining piece on that
        // prerelease, which would admit `1.0.1-alpha`.
        let lhs = VersionSetSpecifier.ranges(["1.0.0-alpha"..<"1.0.1", "2.0.0"..<"3.0.0"])
        let rhs = VersionSetSpecifier.range("1.0.1-beta"..<"2.0.0-alpha")
        XCTAssertFalse(lhs.contains("1.0.1-alpha"))

        let difference = lhs.difference(rhs)
        XCTAssertEqual(difference, lhs)
        XCTAssertFalse(difference.contains("1.0.1-alpha"))
        XCTAssertFalse(difference.contains("1.0.1-beta"))
        XCTAssertTrue(difference.contains("1.0.0-beta"))
        XCTAssertTrue(difference.contains("1.0.0"))
        XCTAssertTrue(difference.contains("2.0.0"))
    }

    func testPrereleaseRangeDifferenceMembershipLawsForRepresentableSamples() {
        // A positive union of the public Range-based cases cannot retain
        // prereleases that share the core of a removed release without also
        // readmitting that release. The samples below cover every other side
        // of the split; the full matrix above enforces safe underapproximation.
        let cases: [(VersionSetSpecifier, VersionSetSpecifier, [Version])] = [
            (
                .range("1.0.0-alpha"..<"2.0.0"),
                .exact("1.0.0"),
                ["1.0.0", "1.0.1-alpha", "1.0.1", "1.5.0-beta", "1.9.0", "2.0.0-alpha"]
            ),
            (
                .range("1.0.0-alpha"..<"2.0.0"),
                .exact("1.5.0"),
                ["1.0.0-alpha", "1.0.0", "1.0.1-alpha", "1.5.0", "1.5.1-alpha", "1.9.0"]
            ),
            (
                .range("0.9.0"..<"2.0.0-alpha"),
                .exact("1.5.0"),
                ["0.9.0", "1.0.0-alpha", "1.0.0", "1.0.1-alpha", "1.5.0", "1.5.1-alpha"]
            ),
            (
                .range("1.0.0-alpha"..<"1.0.1-alpha"),
                .exact("1.0.0-beta"),
                ["1.0.0-alpha", "1.0.0-beta", "1.0.0-beta.0", "1.0.0", "1.0.1-alpha"]
            ),
            (
                .range("1.0.0-alpha"..<"2.0.0"),
                .range("1.0.0-beta"..<"2.0.0"),
                ["1.0.0-alpha", "1.0.0-beta", "1.0.0", "1.0.1-alpha", "1.9.0"]
            ),
            (
                .range("1.0.0"..<"2.0.0"),
                .exact("1.5.0-alpha").union(.exact("1.5.0-alpha.0")),
                ["1.0.0", "1.4.0-beta", "1.5.0-alpha", "1.5.0-alpha.0", "1.5.0", "1.9.0"]
            ),
            (
                .range("1.0.0"..<"2.0.0"),
                .range("1.4.0-alpha"..<"1.6.0-beta"),
                ["1.3.0", "1.4.0-beta", "1.4.0", "1.5.0", "1.6.0-alpha", "1.6.0", "1.7.0-alpha"]
            ),
        ]

        for (lhs, rhs, versions) in cases {
            let result = lhs.difference(rhs)
            for version in versions {
                XCTAssertEqual(
                    result.contains(version),
                    lhs.contains(version) && !rhs.contains(version),
                    "difference membership mismatch for \(lhs), \(rhs), and \(version)"
                )
            }
        }
    }

    func testFiniteSetAlgebraMembershipLaws() {
        let versions: [Version] = [
            "1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5",
        ]
        // Prerelease membership is only approximated (see
        // `testPrereleaseRangeDifferenceMembershipLawsForRepresentableSamples`),
        // so these are checked against the soundness laws of difference only.
        let prereleaseVersions: [Version] = [
            "1.0.1-alpha", "1.0.1-beta", "1.0.2-alpha", "1.0.2-alpha.0",
            "1.0.2-alpha.0.0", "1.0.3-alpha", "1.0.3-beta",
        ]
        let sets: [VersionSetSpecifier] = [
            .empty,
            .exact("1.0.1"),
            .range("1.0.0"..<"1.0.4"),
            .ranges(["1.0.0"..<"1.0.2", "1.0.3"..<"1.0.5"]),
            .exact("1.0.2").union(.range("1.0.4"..<"1.0.6")),
            .range("1.0.1-alpha"..<"1.0.3-beta"),
            .exact("1.0.2-alpha").union(.exact("1.0.2-alpha.0")),
        ]

        for lhs in sets {
            XCTAssertEqual(lhs.intersection(lhs), lhs)
            XCTAssertEqual(lhs.union(lhs), lhs)

            for rhs in sets {
                XCTAssertEqual(lhs.union(rhs), rhs.union(lhs))
                XCTAssertEqual(lhs.intersection(rhs), rhs.intersection(lhs))

                for version in versions {
                    XCTAssertEqual(
                        lhs.union(rhs).contains(version),
                        lhs.contains(version) || rhs.contains(version),
                        "union membership mismatch for \(lhs), \(rhs), and \(version)"
                    )
                    XCTAssertEqual(
                        lhs.intersection(rhs).contains(version),
                        lhs.contains(version) && rhs.contains(version),
                        "intersection membership mismatch for \(lhs), \(rhs), and \(version)"
                    )
                    XCTAssertEqual(
                        lhs.difference(rhs).contains(version),
                        lhs.contains(version) && !rhs.contains(version),
                        "difference membership mismatch for \(lhs), \(rhs), and \(version)"
                    )
                }

                let difference = lhs.difference(rhs)
                for version in prereleaseVersions where difference.contains(version) {
                    XCTAssertTrue(
                        lhs.contains(version),
                        "difference admitted \(version) outside \(lhs) minus \(rhs)"
                    )
                    XCTAssertFalse(
                        rhs.contains(version),
                        "difference readmitted \(version) for \(lhs) minus \(rhs)"
                    )
                }
            }
        }
    }

    func testEquality() {
        // Basic cases.
        XCTAssertTrue(VersionSetSpecifier.any == VersionSetSpecifier.any)
        XCTAssertTrue(VersionSetSpecifier.empty == VersionSetSpecifier.empty)
        XCTAssertTrue(VersionSetSpecifier.range("1.0.0"..<"5.0.0") == VersionSetSpecifier.range("1.0.0"..<"5.0.0"))
        XCTAssertTrue(VersionSetSpecifier.exact("1.2.3") == VersionSetSpecifier.exact("1.2.3"))
        XCTAssertTrue(VersionSetSpecifier.ranges(["3.2.0"..<"3.2.1", "3.2.3"..<"4.0.0"]) == VersionSetSpecifier.ranges(["3.2.0"..<"3.2.1", "3.2.3"..<"4.0.0"]))

        // Empty is equivalent to an empty list of ranges or if the list contains one range where the lower bound equals the upper bound.
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

    func testEqualRepresentationsHaveEqualHashes() {
        let afterBeta = Version(2, 0, 1, prereleaseIdentifiers: ["beta", String(Int.min)])
        let equivalentSets: [[VersionSetSpecifier]] = [
            [.empty, .range("2.0.0"..<"2.0.0"), .ranges([])],
            [.exact("2.0.1"), .range("2.0.1"..<"2.0.2"), .ranges(["2.0.1"..<"2.0.2"])],
            [
                .exact("2.0.1-beta"),
                .range("2.0.1-beta"..<afterBeta),
                .ranges(["2.0.1-beta"..<afterBeta]),
            ],
            [
                .range("1.0.0"..<"2.0.0"),
                .ranges(["1.0.0"..<"1.5.0", "1.5.0"..<"2.0.0"]),
            ],
            // Numeric prerelease identifiers compare by value, not spelling.
            [.exact("1.0.0-0"), .exact("1.0.0-00"), .exact("1.0.0--0")],
            [
                .range("1.0.0-0"..<"1.0.0-beta"),
                .ranges(["1.0.0--0"..<"1.0.0-alpha", "1.0.0-alpha"..<"1.0.0-beta"]),
            ],
            // `Version.==` ignores the identifiers after such a pair.
            [
                .range("1.0.0-0.alpha"..<"1.0.1"),
                .ranges(["1.0.0-00.beta"..<"1.0.0-z", "1.0.0-z"..<"1.0.1"]),
            ],
        ]

        for representations in equivalentSets {
            for lhs in representations {
                for rhs in representations {
                    XCTAssertEqual(lhs, rhs)
                    XCTAssertEqual(lhs.hashValue, rhs.hashValue)
                    XCTAssertTrue(Set([lhs]).contains(rhs))
                }
            }
        }
    }

    func testRangePastNumericallyEqualSuccessorIsNotExact() {
        // `Version.==` stops at differently spelled, numerically equal
        // identifiers, so `upper` compares equal to the successor of
        // `1.0.0-alpha` although the range also contains `version`.
        let minimum = "-0" + String(Int.min).dropFirst()
        let upper = Version(1, 0, 0, prereleaseIdentifiers: ["alpha", minimum, "foo"])
        let version = Version(1, 0, 0, prereleaseIdentifiers: ["alpha", minimum, "aaa"])
        let range = VersionSetSpecifier.range("1.0.0-alpha"..<upper)
        XCTAssertEqual(upper, Version("1.0.0-alpha").exactRange.upperBound)

        XCTAssertFalse(range.isExact)
        XCTAssertTrue(range.contains(version))
        XCTAssertTrue(range.union(.empty).contains(version))
        XCTAssertEqual(range.intersection(.exact(version)), .exact(version))
        XCTAssertFalse(VersionSetSpecifier.range("1.0.0-0"..<"2.0.0").difference(range).contains(version))

        let ranges = VersionSetSpecifier.ranges(["1.0.0-alpha"..<upper, "2.0.0"..<"3.0.0"])
        XCTAssertEqual(ranges.description, "{1.0.0-alpha..<\(upper), 2.0.0..<3.0.0}")
    }

    func testRangesDescriptionKeepsUpperBounds() {
        // Only the single `.range` form patches a `.max` upper bound, as before.
        let upper = Version(1, 0, .max, prereleaseIdentifiers: ["alpha"])
        let ranges = VersionSetSpecifier.ranges(["1.0.0"..<upper, "2.0.0"..<"3.0.0"])
        XCTAssertEqual(ranges.description, "{1.0.0..<\(upper), 2.0.0..<3.0.0}")
        XCTAssertEqual(VersionSetSpecifier.range("1.0.0"..<Version(1, 0, .max)).description, "1.0.0..<1.1.0")
    }

    func testPrereleaseExactSetAlgebra() {
        let alpha: Version = "1.0.0-alpha"
        let alphaZero: Version = "1.0.0-alpha.0"
        let beta: Version = "1.0.0-beta"
        let betaZero: Version = "1.0.0-beta.0"
        let release: Version = "1.0.0"
        let nextRelease: Version = "1.0.1"

        let prereleaseRange = VersionSetSpecifier.range(alpha..<"1.0.1-alpha")
        let stableRange = VersionSetSpecifier.range(release..<"1.0.1")
        let mixed = VersionSetSpecifier.exact(beta).union(stableRange)

        XCTAssertTrue(mixed.contains(beta))
        XCTAssertTrue(mixed.contains(release))
        XCTAssertEqual(mixed.intersection(.exact(beta)), .exact(beta))
        XCTAssertEqual(stableRange.intersection(.exact(beta)), .empty)
        XCTAssertEqual(stableRange.difference(.exact(beta)), stableRange)
        XCTAssertEqual(VersionSetSpecifier.exact(beta).difference(stableRange), .exact(beta))

        let withoutBeta = prereleaseRange.difference(.exact(beta))
        XCTAssertTrue(withoutBeta.contains(alpha))
        XCTAssertTrue(withoutBeta.contains(alphaZero))
        XCTAssertFalse(withoutBeta.contains(beta))
        XCTAssertTrue(withoutBeta.contains("1.0.0-beta.0"))
        XCTAssertTrue(withoutBeta.contains(release))

        let adjacent = VersionSetSpecifier.ranges([
            alpha..<beta,
            beta..<"1.0.1-alpha",
        ])
        let merged = VersionSetSpecifier.range(alpha..<"1.0.1-alpha")
        XCTAssertEqual(adjacent, merged)
        XCTAssertEqual(adjacent.hashValue, merged.hashValue)

        let emptyPrereleaseRange = VersionSetSpecifier.range(alpha..<alpha)
        XCTAssertEqual(emptyPrereleaseRange, .empty)
        XCTAssertFalse(emptyPrereleaseRange.contains(alpha))

        let sampledVersions = [alpha, alphaZero, beta, betaZero, release, nextRelease]
        let sampledSets: [VersionSetSpecifier] = [
            .empty,
            .exact(alpha),
            .exact(alphaZero),
            .exact(beta),
            stableRange,
            mixed,
        ]
        for lhs in sampledSets {
            for rhs in sampledSets {
                XCTAssertEqual(lhs.union(rhs), rhs.union(lhs))
                XCTAssertEqual(lhs.intersection(rhs), rhs.intersection(lhs))
                for version in sampledVersions {
                    XCTAssertEqual(
                        lhs.union(rhs).contains(version),
                        lhs.contains(version) || rhs.contains(version)
                    )
                    XCTAssertEqual(
                        lhs.intersection(rhs).contains(version),
                        lhs.contains(version) && rhs.contains(version)
                    )
                    XCTAssertEqual(
                        lhs.difference(rhs).contains(version),
                        lhs.contains(version) && !rhs.contains(version)
                    )
                }
            }
        }
    }

    func testNegativeNumericPrereleaseIdentifiers() {
        // Numeric prerelease identifiers compare numerically, negative values
        // included, so `"0"` is not the smallest identifier of a core.
        let negative: Version = "1.0.1--1"
        XCTAssertLessThan(negative, "1.0.1-0")

        let releaseBounded = VersionSetSpecifier.range("1.0.0-alpha"..<"1.0.1")
        let prereleaseBounded = VersionSetSpecifier.range("1.0.0-alpha"..<"1.0.1-0")
        XCTAssertFalse(releaseBounded.contains(negative))
        XCTAssertTrue(prereleaseBounded.contains(negative))
        XCTAssertNotEqual(releaseBounded, prereleaseBounded)
        XCTAssertEqual(releaseBounded.intersection(.exact(negative)), .empty)
        XCTAssertEqual(prereleaseBounded.intersection(.exact(negative)), .exact(negative))

        let exactAlpha = VersionSetSpecifier.exact("1.0.0-alpha")
        XCTAssertFalse(exactAlpha.contains("1.0.0-alpha.-1"))
        XCTAssertFalse(exactAlpha.union(.exact("2.0.0")).contains("1.0.0-alpha.-1"))
        XCTAssertNotEqual(exactAlpha, .range("1.0.0-alpha"..<"1.0.0-alpha.0"))

        let withoutRelease = VersionSetSpecifier.range("1.0.0-alpha"..<"2.0.0").difference(.exact("1.2.3"))
        XCTAssertFalse(withoutRelease.contains("1.2.3"))
        XCTAssertTrue(withoutRelease.contains("1.2.4--1"))
        XCTAssertTrue(withoutRelease.contains("1.2.4"))

        // Diagnostics spell the internal floor identifier as `0`.
        let withoutBeta = VersionSetSpecifier.range("1.0.0-beta"..<"2.0.0").difference(.exact("1.0.0-beta"))
        XCTAssertEqual(withoutBeta.diagnosticDescription, "1.0.0-beta.0..<2.0.0")
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

        let mixed = VersionSetSpecifier.exact("1.2.0-beta")
            .union(.range("1.3.0"..<"2.0.0"))
        let releasesOnly = mixed.withoutPrereleases
        XCTAssertEqual(
            releasesOnly,
            VersionSetSpecifier.exact("1.2.0").union(.range("1.3.0"..<"2.0.0"))
        )
        XCTAssertTrue(releasesOnly.contains("1.2.0"))
        XCTAssertFalse(releasesOnly.supportsPrereleases)
    }

    func testExactVersionAtIntegerBoundaries() {
        // An exact requirement is modelled as `version..<successor`, so a
        // component at `Int.max` must carry into the next one rather than
        // overflow. `Version(.max, .max, .max)` has no successor; see
        // `testExactMaximumVersion`.
        let cases: [(version: Version, successor: Version)] = [
            (Version(1, 2, .max), Version(1, 3, 0)),
            (Version(1, .max, .max), Version(2, 0, 0)),
        ]

        for (version, successor) in cases {
            let exact = VersionSetSpecifier.exact(version)
            let asRange = VersionSetSpecifier.range(version ..< successor)

            XCTAssertEqual(exact.description, version.description)
            XCTAssertEqual(exact, asRange)
            XCTAssertEqual(exact.hashValue, asRange.hashValue)
            XCTAssertTrue(exact.contains(version))
            XCTAssertFalse(exact.contains(successor))
            XCTAssertEqual(exact.intersection(exact), exact)

            let other = VersionSetSpecifier.exact("1.0.0")
            let union = exact.union(other)
            XCTAssertTrue(union.contains(version))
            XCTAssertTrue(union.contains("1.0.0"))
            XCTAssertEqual(union.difference(exact), other)
        }
    }

    func testExactMaximumVersion() {
        // `Version(.max, .max, .max)` has no successor, so `.exact` encodes it
        // as the zero-width range `max..<max`: the one zero-width range that
        // denotes a version instead of the empty set.
        let max = Version(.max, .max, .max)
        let exact = VersionSetSpecifier.exact(max)
        let representations: [VersionSetSpecifier] = [exact, .range(max..<max), .ranges([max..<max])]

        for representation in representations {
            XCTAssertEqual(representation, exact)
            XCTAssertEqual(representation.hashValue, exact.hashValue)
            XCTAssertNotEqual(representation, .empty)
            XCTAssertEqual(representation.description, max.description)
            XCTAssertTrue(representation.contains(max))
            XCTAssertFalse(representation.contains(Version(.max, .max, .max - 1)))
            XCTAssertTrue(representation.isExact)
            XCTAssertFalse(representation.supportsPrereleases)
        }
        XCTAssertEqual(Set(representations).count, 1)

        XCTAssertEqual(exact.union(exact), exact)
        XCTAssertEqual(exact.intersection(exact), exact)
        XCTAssertEqual(exact.difference(exact), .empty)

        // `max` lies just past every range that ends at it, so a union with
        // such a range must keep both pieces instead of merging them.
        let below = VersionSetSpecifier.range("1.0.0"..<max)
        XCTAssertFalse(below.contains(max))
        let union = below.union(exact)
        XCTAssertEqual(union, exact.union(below))
        XCTAssertNotEqual(union, below)
        XCTAssertTrue(union.contains("1.0.0"))
        XCTAssertTrue(union.contains(max))
        XCTAssertEqual(union.description, "{1.0.0..<\(max), \(max)}")

        XCTAssertEqual(below.intersection(exact), .empty)
        XCTAssertEqual(exact.intersection(below), .empty)
        XCTAssertEqual(union.intersection(exact), exact)
        XCTAssertEqual(union.intersection(below), below)
        XCTAssertEqual(below.difference(exact), below)
        XCTAssertEqual(exact.difference(below), exact)
        XCTAssertEqual(union.difference(below), exact)
        XCTAssertEqual(union.difference(exact), below)

        let mixed = VersionSetSpecifier.exact("1.0.0").union(exact)
        XCTAssertTrue(mixed.contains("1.0.0"))
        XCTAssertTrue(mixed.contains(max))
        XCTAssertEqual(mixed.intersection(below), .exact("1.0.0"))
        XCTAssertEqual(mixed.intersection(union), mixed)
        XCTAssertEqual(mixed.difference(.exact("1.0.0")), exact)
        XCTAssertEqual(mixed.difference(below), exact)

        // Prereleases of `max` keep their ordinary encoding, and dropping the
        // prerelease identifiers lands on the `max` point.
        let maxPrerelease = Version(.max, .max, .max, prereleaseIdentifiers: ["alpha"])
        let exactPrerelease = VersionSetSpecifier.exact(maxPrerelease)
        XCTAssertNotEqual(exactPrerelease, exact)
        XCTAssertTrue(exactPrerelease.contains(maxPrerelease))
        XCTAssertFalse(exactPrerelease.contains(max))
        XCTAssertEqual(exactPrerelease.withoutPrereleases, exact)
        XCTAssertTrue(exactPrerelease.withoutPrereleases.contains(max))
        XCTAssertEqual(exactPrerelease.union(exact).withoutPrereleases, exact)
        XCTAssertEqual(VersionSetSpecifier.range(maxPrerelease..<max), .empty)
    }

    func testExactVersionsWithBuildMetadataHashConsistentlyWithEquality() {
        let lhs = VersionSetSpecifier.exact("1.2.3+first")
        let rhs = VersionSetSpecifier.exact("1.2.3+second")

        // Whether build metadata takes part in equality is tracked separately
        // (#10391); this only checks that hashing agrees with `==`.
        if lhs == rhs {
            XCTAssertEqual(lhs.hashValue, rhs.hashValue)
            XCTAssertEqual(Set([lhs, rhs]).count, 1)
        } else {
            XCTAssertEqual(Set([lhs, rhs]).count, 2)
        }
    }
}

private extension VersionSetSpecifier {
    /// Membership that ignores the prerelease admission rules of
    /// `Range.contains(version:)`, i.e. a plain `lowerBound <= version <
    /// upperBound` test. Used to bound how far prerelease inference may widen
    /// an intersection.
    func ordinallyContains(_ version: Version) -> Bool {
        func contains(_ range: Range<Version>) -> Bool {
            range.lowerBound <= version && version < range.upperBound
        }

        switch self {
        case .any:
            return true
        case .empty:
            return false
        case .exact(let exact):
            return exact == version
        case .range(let range):
            return contains(range)
        case .ranges(let ranges):
            return ranges.contains(where: contains)
        }
    }
}
