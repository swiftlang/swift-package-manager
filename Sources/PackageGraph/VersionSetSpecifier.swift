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

import Basics
import struct TSCUtility.Version

/// The canonical representation used for version sets that cannot be expressed by a range alone.
///
/// This is public only because it is carried by a public enum. SwiftPM constructs these values
/// internally while resolving dependencies.
@_spi(SwiftPMInternal)
public struct _VersionSetSpecifierSet {
    package let ranges: [Range<Version>]
    package let identifierOverrides: [VersionIdentifierKey: Bool]

    package init(
        ranges: [Range<Version>],
        identifierOverrides: [VersionIdentifierKey: Bool]
    ) {
        self.ranges = ranges
        self.identifierOverrides = identifierOverrides
    }
}

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

    /// A resolver-only set containing ranges and identifier-specific membership overrides.
    @_spi(SwiftPMInternal)
    case _set(_VersionSetSpecifierSet)
}

extension VersionSetSpecifier: Equatable {
    public static func ==(lhs: VersionSetSpecifier, rhs: VersionSetSpecifier) -> Bool {
        if case .any = lhs {
            if case .any = rhs { return true }
            return false
        }
        if case .any = rhs { return false }
        return lhs.canonicalSet.isEqual(to: rhs.canonicalSet)
    }
}

extension VersionSetSpecifier {
    public func hash(into hasher: inout Hasher) {
        if case .any = self {
            hasher.combine(0)
            return
        }

        hasher.combine(1)
        self.canonicalSet.hash(into: &hasher)
    }
}

extension VersionSetSpecifier {
    var isExact: Bool {
        switch self {
        case .any, .empty, .range, .ranges, ._set:
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
        Self.makeSet(ranges: ranges, identifierOverrides: [:])
    }

    public func union(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any), (.any, _):
            return .any
        default:
            return Self.combine(self.canonicalSet, rhs.canonicalSet, base: Self.unionRanges, membership: { $0 || $1 })
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
        default:
            return Self.combine(self.canonicalSet, rhs.canonicalSet, base: Self.intersectRanges, membership: { $0 && $1 })
        }
    }
}

extension VersionSetSpecifier {
    public func difference(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any):
            return .empty
        case (.any, _):
            fatalError("\(#file):\(#line) - Illegal call of \(#function) on left hand side value of `.any`")
        case (.empty, _):
            return .empty
        case (_, .empty):
            return self
        default:
            return Self.combine(self.canonicalSet, rhs.canonicalSet, base: Self.subtractRanges, membership: { $0 && !$1 })
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
            return VersionIdentifierKey(v) == VersionIdentifierKey(version)
        case ._set(let set):
            return set.contains(version)
        }
    }
}

private extension VersionSetSpecifier {
    var canonicalSet: _VersionSetSpecifierSet {
        switch self {
        case .any:
            preconditionFailure("the universal set has no finite range representation")
        case .empty:
            return .init(ranges: [], identifierOverrides: [:])
        case .range(let range):
            return .init(ranges: Self.normalizeRanges([range]), identifierOverrides: [:])
        case .ranges(let ranges):
            return .init(ranges: Self.normalizeRanges(ranges), identifierOverrides: [:])
        case .exact(let version):
            return .init(ranges: [], identifierOverrides: [VersionIdentifierKey(version): true])
        case ._set(let set):
            return Self.canonicalize(set)
        }
    }

    static func combine(
        _ lhs: _VersionSetSpecifierSet,
        _ rhs: _VersionSetSpecifierSet,
        base operation: ([Range<Version>], [Range<Version>]) -> [Range<Version>],
        membership: (Bool, Bool) -> Bool
    ) -> VersionSetSpecifier {
        let ranges = operation(lhs.ranges, rhs.ranges)
        let keys = Set(lhs.identifierOverrides.keys).union(rhs.identifierOverrides.keys)
        var overrides: [VersionIdentifierKey: Bool] = [:]

        for key in keys {
            let included = membership(lhs.contains(key.version), rhs.contains(key.version))
            if included != Self.ranges(ranges, contain: key.version) {
                overrides[key] = included
            }
        }

        return Self.makeSet(ranges: ranges, identifierOverrides: overrides)
    }

    static func makeSet(
        ranges: [Range<Version>],
        identifierOverrides: [VersionIdentifierKey: Bool]
    ) -> VersionSetSpecifier {
        let set = Self.canonicalize(.init(ranges: ranges, identifierOverrides: identifierOverrides))
        if set.ranges.isEmpty {
            if set.identifierOverrides.isEmpty {
                return .empty
            }
            if set.identifierOverrides.count == 1,
               let override = set.identifierOverrides.first,
               override.value
            {
                return .exact(override.key.version)
            }
        }
        if set.identifierOverrides.isEmpty {
            if set.ranges.count == 1 {
                return .range(set.ranges[0])
            }
            return .ranges(set.ranges)
        }
        return ._set(set)
    }

    static func canonicalize(_ set: _VersionSetSpecifierSet) -> _VersionSetSpecifierSet {
        let ranges = Self.normalizeRanges(set.ranges)
        let overrides = set.identifierOverrides.filter { key, included in
            included != Self.ranges(ranges, contain: key.version)
        }
        return .init(ranges: ranges, identifierOverrides: overrides)
    }

    static func normalizeRanges(_ ranges: [Range<Version>]) -> [Range<Version>] {
        let sorted = ranges
            .filter { $0.lowerBound < $0.upperBound }
            .sorted { lhs, rhs in
                if lhs.lowerBound == rhs.lowerBound {
                    return lhs.upperBound < rhs.upperBound
                }
                return lhs.lowerBound < rhs.lowerBound
            }
        var result: [Range<Version>] = []
        for range in sorted {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    static func unionRanges(_ lhs: [Range<Version>], _ rhs: [Range<Version>]) -> [Range<Version>] {
        Self.normalizeRanges(lhs + rhs)
    }

    static func intersectRanges(_ lhs: [Range<Version>], _ rhs: [Range<Version>]) -> [Range<Version>] {
        var result: [Range<Version>] = []
        for left in lhs {
            for right in rhs {
                let lower = max(left.lowerBound, right.lowerBound)
                let upper = min(left.upperBound, right.upperBound)
                if lower < upper {
                    result.append(lower..<upper)
                }
            }
        }
        return Self.normalizeRanges(result)
    }

    static func subtractRanges(_ lhs: [Range<Version>], _ rhs: [Range<Version>]) -> [Range<Version>] {
        var result: [Range<Version>] = []
        for left in lhs {
            var fragments = [left]
            for right in rhs {
                fragments = fragments.flatMap { fragment -> [Range<Version>] in
                    guard fragment.overlaps(right) else { return [fragment] }
                    var remainder: [Range<Version>] = []
                    if fragment.lowerBound < right.lowerBound {
                        remainder.append(fragment.lowerBound..<min(fragment.upperBound, right.lowerBound))
                    }
                    if right.upperBound < fragment.upperBound {
                        remainder.append(max(fragment.lowerBound, right.upperBound)..<fragment.upperBound)
                    }
                    return remainder
                }
            }
            result.append(contentsOf: fragments)
        }
        return Self.normalizeRanges(result)
    }

    static func ranges(_ ranges: [Range<Version>], contain version: Version) -> Bool {
        ranges.contains { $0.contains(version: version) }
    }
}

private extension _VersionSetSpecifierSet {
    func contains(_ version: Version) -> Bool {
        self.identifierOverrides[VersionIdentifierKey(version)] ??
            self.ranges.contains { $0.contains(version: version) }
    }

    func isEqual(to other: Self) -> Bool {
        self.ranges == other.ranges && self.identifierOverrides == other.identifierOverrides
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.ranges.count)
        for range in self.ranges {
            hasher.combine(range.lowerBound)
            hasher.combine(range.upperBound)
        }
        let overrides = self.identifierOverrides.sorted { lhs, rhs in
            lhs.key.version.description < rhs.key.version.description
        }
        hasher.combine(overrides.count)
        for (key, included) in overrides {
            hasher.combine(key)
            hasher.combine(included)
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
        case ._set(let set):
            set.ranges.contains(where: \.supportsPrereleases) ||
                set.identifierOverrides.contains { $0.value && $0.key.version.supportsPrerelease }
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
        case ._set(let set):
            Self.makeSet(
                ranges: set.ranges.map { $0.withoutPrerelease },
                identifierOverrides: Dictionary(
                    grouping: set.identifierOverrides,
                    by: { VersionIdentifierKey($0.key.version.withoutPrerelease) }
                ).compactMapValues { overrides in
                    let memberships = Set(overrides.map(\.value))
                    return memberships.count == 1 ? memberships.first : nil
                }
            )
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
        case ._set(let set):
            let base = Self.union(from: set.ranges).description
            let included = set.identifierOverrides
                .filter(\.value)
                .map { $0.key.version.description }
                .sorted()
            let excluded = set.identifierOverrides
                .filter { !$0.value }
                .map { $0.key.version.description }
                .sorted()
            var components = base == "empty" ? [] : [base]
            if !included.isEmpty {
                components.append("include {\(included.joined(separator: ", "))}")
            }
            if !excluded.isEmpty {
                components.append("exclude {\(excluded.joined(separator: ", "))}")
            }
            return components.joined(separator: ", ")
        }
    }
}

fileprivate extension Range where Bound == Version {
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
