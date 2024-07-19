//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCUtility.Version

/// An abstract definition for a set of versions.
public enum VersionSetSpecifier: Hashable {
    /// The universal set.
    case any

    /// The empty set.
    case empty

    /// A non-empty range of version.
    case range(Range<Version>)

    /// The exact version that is required.
    case exact(Version)

    /// A range of disjoint versions (sorted).
    case ranges([Range<Version>])
}

extension VersionSetSpecifier: Equatable {
    public static func ==(lhs: VersionSetSpecifier, rhs: VersionSetSpecifier) -> Bool {
        switch (lhs, rhs) {
        // Basic cases.
        case (.any, .any):
            return true
        case (.empty, .empty):
            return true
        case (let .range(lhsRange), let .range(rhsRange)):
            return lhsRange == rhsRange
        case (let .exact(lhsExact), let .exact(rhsExact)):
            return lhsExact == rhsExact
        case (let .ranges(lhsRanges), let .ranges(rhsRanges)):
            return lhsRanges == rhsRanges

        // Empty is equivalent to an empty list of ranges or if the list contains one range where the lower bound equals the upper bound.
        case (.empty, let .ranges(ranges)):
            fallthrough
        case (let .ranges(ranges), .empty):
            return ranges.isEmpty || (ranges.count == 1 && ranges[0].lowerBound == ranges[0].upperBound)

        // Empty is equivalent to a range where the lower bound equals the upper bound.
        case (.empty, let .range(range)):
            fallthrough
        case (let .range(range), .empty):
            return range.upperBound == range.lowerBound

        // Exact is equal to a range that spans a single patch.
        case (let .exact(exact), let .range(range)):
            fallthrough
        case (let .range(range), let .exact(exact)):
            return range.lowerBound == exact && range.upperBound == exact.nextPatch()

        // Exact is also equal to a list of ranges with one entry that spans a single patch.
        case (let .exact(exact), let .ranges(ranges)):
            fallthrough
        case (let .ranges(ranges), let .exact(exact)):
            return ranges.count == 1 && ranges[0].lowerBound == exact && ranges[0].upperBound == exact.nextPatch()

        // A range is equal to a list of ranges with that one range.
        case (let .range(range), let .ranges(ranges)):
            fallthrough
        case (let .ranges(ranges), let .range(range)):
            return ranges.count == 1 && ranges[0] == range

        default:
            return false
        }
    }
}

extension VersionSetSpecifier {
    var isExact: Bool {
        switch self {
        case .any, .empty, .range, .ranges:
            return false
        case .exact:
            return true
        }
    }
}

extension VersionSetSpecifier {
    public static func union(from range: Swift.Range<Version>) -> VersionSetSpecifier {
        return .union(from: [range])
    }

    public static func union(from ranges: [Swift.Range<Version>]) -> VersionSetSpecifier {
        switch ranges.count {
        case 0:
            return .empty
        case 1:
            let range = ranges[0]
            // FIXME: Can we avoid this? testConflict1 goes into a loop if we don't do this.
            if range.lowerBound.nextPatch() == range.upperBound {
                return .exact(range.lowerBound)
            }
            return .range(range)
        default:
            let ranges = ranges.sorted(by: { $0.lowerBound < $1.lowerBound })

            var result: [Range<Version>] = []
            for range in ranges {
                // We can merge if next range starts immediately after this one or if they overlap.
                if let last = result.last, last.upperBound == range.lowerBound || range.overlaps(last) || last.lowerBound.nextPatch() == range.lowerBound {
                    let newResult: Range<Version>

                    if range.lowerBound == range.upperBound {
                        // 1.0.0..<1.0.1 U 1.0.1..<1.0.1 is 1.0.0..<1.0.2
                        let version = range.lowerBound
                        if last.upperBound == version {
                            newResult = last.lowerBound ..< version.nextPatch()
                        } else {
                            continue
                        }
                    } else {
                        let lower = min(last.lowerBound, range.lowerBound)
                        let upper = max(last.upperBound, range.upperBound)
                        newResult = lower ..< upper
                    }

                    result[result.count - 1] = newResult
                } else {
                    result.append(range)
                }
            }

            if result.count == 1 {
                return .range(result[0])
            }
            return .ranges(result)
        }
    }

    public func union(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any), (.any, _):
            return .any
        case (.empty, _):
            return rhs
        case (_, .empty):
            return self
        case (.exact(let v1), .exact(let v2)):
            if v1 == v2 {
                return self
            }
            return VersionSetSpecifier.union(from: [v1..<v1, v2..<v2])

        case (.range(let v2), .exact(let v1)),
             (.exact(let v1), .range(let v2)):
            return VersionSetSpecifier.union(from: [v1..<v1, v2])

        case (.ranges(let ranges), .exact(let exact)), (.exact(let exact), .ranges(let ranges)):
            return VersionSetSpecifier.union(from: [exact..<exact] + ranges)

        case (.range(let lhs), .range(let rhs)):
            return VersionSetSpecifier.union(from: [lhs, rhs])

        case (.ranges(let ranges), .range(let range)), (.range(let range), .ranges(let ranges)):
            return VersionSetSpecifier.union(from: [range] + ranges)

        case (.ranges(let r1), .ranges(let r2)):
            return VersionSetSpecifier.union(from: r1 + r2)
        }
    }
}

extension VersionSetSpecifier {
    /// Compute the intersection of two set specifiers.
    public func intersection(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (.any, _):
            return rhs
        case (_, .any):
            return self
        case (.empty, _):
            return .empty
        case (_, .empty):
            return .empty
        case (.range(let lhs), .range(let rhs)):
            if let result = VersionSetSpecifier.intersection(lhs, rhs) {
                return .range(result)
            }
            return .empty
        case (.exact(let v), _):
            if rhs.contains(v) {
                return self
            }
            return .empty
        case (_, .exact(let v)):
            if contains(v) {
                return rhs
            }
            return .empty

        case (.ranges(let ranges), .range(let range)), (.range(let range), .ranges(let ranges)):
            return .intersection(ranges, [range])
        case (.ranges(let lhs), .ranges(let rhs)):
             return .intersection(lhs, rhs)
        }
    }

    fileprivate static func intersection(_ lhs: Range<Version>, _ rhs: Range<Version>) -> Range<Version>? {
        let start = Swift.max(lhs.lowerBound, rhs.lowerBound)
        let end = Swift.min(lhs.upperBound, rhs.upperBound)
        if start < end {
            return start..<end
        }
        return nil
    }

    fileprivate static func intersection(_ lhs: [Range<Version>], _ rhs: [Range<Version>]) -> VersionSetSpecifier {
        var lhsItr = lhs.makeIterator()
        var rhsItr = rhs.makeIterator()

        var currentLhs = lhsItr.next()
        var currentRhs = rhsItr.next()

        var result: [Range<Version>] = []

        while let lhs = currentLhs, let rhs = currentRhs {
            if let current = VersionSetSpecifier.intersection(lhs, rhs) {
                result.append(current)
            }

            // Move the one with lower upper bound so large ranges have a chance to match multiple
            // small ranges they contain.
            if lhs.upperBound < rhs.upperBound {
                currentLhs = lhsItr.next()
            } else {
                currentRhs = rhsItr.next()
            }
        }

        return .union(from: result)
    }
}

extension VersionSetSpecifier {
    public func difference(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any):
            return .empty
        case (.any, _):
            fatalError()
        case (.empty, _):
            return .empty
        case (_, .empty):
            return self
        case (.exact(let v1), .exact(let v2)):
            if v1 == v2 {
                return .empty
            }
            return self

        case (.exact(let lhs), .range(let rhs)):
            if rhs.contains(version: lhs) {
                return .empty
            }
            return .exact(lhs)
        case (.range(let lhs), .exact(let rhs)):
            if !lhs.contains(version: rhs) {
                return .range(lhs)
            }

            if lhs.lowerBound == rhs {
                // Return empty if the range is empty. This means upper and lower bounds are equal since the range is half-open and there are no negative results here.
                if lhs.lowerBound == lhs.upperBound {
                    return .empty
                }
                // If there is exactly one patch between lower and upper bound, the range represent the lower bound as an exact version. So the range is empty in this case as well.
                if lhs.lowerBound.nextPatch() == lhs.upperBound {
                    return .empty
                }
                return .range(rhs.nextPatch()..<lhs.upperBound)
            }

            return .union(from: [lhs.lowerBound..<rhs, rhs.nextPatch()..<lhs.upperBound])

        case (.ranges(let ranges), .exact(let exact)):
            var result = [Range<Version>]()

            for range in ranges {
                // FIXME: is this worth merging with the logic in (range, exact) case above?
                if !range.contains(version: exact) {
                    result.append(range)
                } else if range.lowerBound == exact {
                    if range.lowerBound == range.upperBound {
                        continue
                    }

                    if exact.nextPatch() < range.upperBound {
                        result.append(exact.nextPatch()..<range.upperBound)
                    }
                } else {
                    result += [range.lowerBound..<exact]
                    if exact.nextPatch() < range.upperBound {
                        result += [exact.nextPatch()..<range.upperBound]
                    }
                }
            }
            return .union(from: result)

        case (.exact(let exact), .ranges(let ranges)):
            for range in ranges {
                if range.contains(version: exact) {
                    return .empty
                }
            }
            return self

        case (.range(let lhs), .range(let rhs)):
            if lhs == rhs { return .empty }
            if !lhs.overlaps(rhs) { return .range(lhs) }

            var result = [Range<Version>]()
            if lhs.lowerBound < rhs.lowerBound {
                result.append(lhs.lowerBound..<rhs.lowerBound)
            }

            if rhs.upperBound < lhs.upperBound {
                result.append(rhs.upperBound..<lhs.upperBound)
            }
            return .union(from: result)

        case (.range(let inputRange), .ranges(let ranges)):
            var result = [Range<Version>]()
            var lhs = inputRange
            for range in ranges {
                // Skip the ranges that don't overlap with the current lhs range.
                // FIXME: We can exit the loop early when the range goes above lhs.
                if !range.overlaps(lhs) { continue }

                let diff = VersionSetSpecifier.range(lhs).difference(.range(range))
                switch diff {
                case .empty:
                    return .empty
                case .any:
                    fatalError("unexpected any result")
                case .exact(let v):
                    lhs = v..<v.nextPatch()
                case .range(let r):
                    lhs = r
                case .ranges(let rs):
                    // If the difference end up being a disjoint set, append the first one to
                    // our result and continue reducing the second set.
                    precondition(rs.count == 2, "expected 2 elements in ranges \(rs)")
                    result.append(rs[0])
                    lhs = rs[1]
                }
            }
            return .union(from: result + [lhs])

        case (.ranges(_), .range(let r)):
            return self.difference(.ranges([r]))

        case (.ranges(let lhs), .ranges(let rhs)):
            // Based on the difference method in https://github.com/dart-lang/pub_semver/blob/master/lib/src/version_union.dart
            var lhsItr = lhs.makeIterator()
            var rhsItr = rhs.makeIterator()

            var currentLHS = lhsItr.next()!
            var currentRHS = rhsItr.next()!

            var result: [Range<Version>] = []

            func moveRHS() -> Bool {
                if let value = rhsItr.next() {
                    currentRHS = value
                    return true
                }

                // RHS is done so add remaining on LHS ranges to the final result.
                result.append(currentLHS)
                while let value = lhsItr.next() {
                    result.append(value)
                }
                return false
            }

            func moveLHS(addCurrentLHS: Bool = true) -> Bool {
                if addCurrentLHS {
                    result.append(currentLHS)
                }

                if let value = lhsItr.next() {
                    currentLHS = value
                    return true
                }
                return false
            }

            outer: while true {
                if currentRHS.isLowerThan(currentLHS) {
                    if !moveRHS() { break outer }
                    continue
                }

                if currentRHS.isHigherThan(currentLHS) {
                    if !moveLHS() { break outer }
                    continue
                }

                var diff = VersionSetSpecifier.range(currentLHS).difference(.range(currentRHS))
                // Transform exact to a range so it is handled in the range case below.
                if case .exact(let v) = diff {
                    diff = .range(v..<v.nextPatch())
                }

                switch diff {
                case .empty:
                    if !moveLHS(addCurrentLHS: false) { break outer }
                case .any, .exact:
                    fatalError("Unexpected result \(diff)")
                case .range(let r):
                    currentLHS = r
                    // Move the one with lower upper bound so large ranges have a chance to match multiple
                    // small ranges they contain.
                    if currentLHS.upperBound < currentRHS.upperBound {
                        if !moveRHS() { break outer }
                    } else {
                        if !moveLHS() { break outer }
                    }
                case .ranges(let rs):
                    // If the difference end up being a disjoint set, append the first one to
                    // our result and continue reducing the second set.
                    precondition(rs.count == 2, "expected 2 elements in ranges \(rs)")
                    result.append(rs[0])
                    currentLHS = rs[1]
                    if !moveRHS() { break outer }
                }
            }

            return .union(from: result)
        }
    }
}

extension VersionSetSpecifier {
    /// Check if the set contains a version.
    public func contains(_ version: Version) -> Bool {
        switch self {
        case .empty:
            return false
        case .range(let range):
            return range.contains(version: version)
        case .ranges(let ranges):
            return ranges.contains(where: { $0.contains(version: version) })
        case .any:
            return true
        case .exact(let v):
            return v == version
        }
    }
}

extension VersionSetSpecifier {
    package var supportsPrereleases: Bool {
        switch self {
        case .empty, .any:
            false
        case .exact(let version):
            version.supportsPrerelease
        case .range(let range):
            range.supportsPrereleases
        case .ranges(let ranges):
            ranges.contains(where: \.supportsPrereleases)
        }
    }

    package var withoutPrereleases: VersionSetSpecifier {
        if !supportsPrereleases {
            return self
        }

        return switch self {
        case .empty, .any:
            self
        case .range(let range):
            .range(range.withoutPrerelease)
        case .ranges(let ranges):
            .ranges(ranges.map { $0.withoutPrerelease })
        case .exact(let version):
            .exact(version.withoutPrerelease)
        }
    }
}

extension VersionSetSpecifier: CustomStringConvertible {
    public var description: String {
        switch self {
        case .any:
            return "any"
        case .empty:
            return "empty"
        case .ranges(let ranges):
            return "{" + ranges.map{
                if $0.lowerBound == $0.upperBound {
                    return $0.lowerBound.description
                }
                return $0.lowerBound.description + "..<" + $0.upperBound.description
            }.joined(separator: ", ") + "}"
        case .range(let range):
            var upperBound = range.upperBound
            // Patch the version range representation. This shouldn't be
            // required once we have custom version range structure.
            if upperBound.minor == .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major + 1, 0, 0)
            }
            if upperBound.minor != .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major, upperBound.minor + 1, 0)
            }
            return range.lowerBound.description + "..<" + upperBound.description
        case .exact(let version):
            return version.description
        }
    }
}

fileprivate extension Range where Bound == Version {
    func isLowerThan(_ other: Range<Bound>) -> Bool {
        return self.lowerBound < other.lowerBound && self.upperBound < other.upperBound
    }

    func isHigherThan(_ other: Range<Bound>) -> Bool {
        return other.isLowerThan(self)
    }

    var supportsPrereleases: Bool {
        self.lowerBound.supportsPrerelease || self.upperBound.supportsPrerelease
    }

    var withoutPrerelease: Range<Version> {
        if !supportsPrereleases {
            return self
        }

        return Range(uncheckedBounds: (
            lower: self.lowerBound.withoutPrerelease,
            upper: self.upperBound.withoutPrerelease
        ))
    }
}

fileprivate extension Version {
    var supportsPrerelease: Bool {
        !self.prereleaseIdentifiers.isEmpty
    }

    var withoutPrerelease: Version {
        Version(
            self.major,
            self.minor,
            self.patch,
            prereleaseIdentifiers: [],
            buildMetadataIdentifiers: self.buildMetadataIdentifiers
        )
    }
}
