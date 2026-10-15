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

    /// A sorted list of normalized version ranges.
    ///
    /// Ranges can overlap in version ordering when they differ in whether
    /// prerelease versions are admitted.
    case ranges([Range<Version>])
}

extension VersionSetSpecifier: Equatable {
    public static func ==(lhs: VersionSetSpecifier, rhs: VersionSetSpecifier) -> Bool {
        switch (lhs, rhs) {
        case (.any, .any):
            return true
        case (.any, _), (_, .any):
            return false
        default:
            return lhs.semanticSignature == rhs.semanticSignature
        }
    }
}

extension VersionSetSpecifier {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .any:
            hasher.combine(0 as UInt8)
        default:
            hasher.combine(1 as UInt8)
            hasher.combine(self.semanticSignature)
        }
    }
}

fileprivate struct FiniteVersionSet: Hashable {
    let releases: [Range<Version>]
    let prereleases: [Range<Version>]

    // `Version.==` compares numeric prerelease identifiers by value, so
    // `1.0.0-0`, `1.0.0-00` and `1.0.0--0` are equal, while
    // `Version.hash(into:)` hashes their spelling. Hash the bounds in a way
    // that agrees with the synthesized `==`.
    func hash(into hasher: inout Hasher) {
        for ranges in [self.releases, self.prereleases] {
            hasher.combine(ranges.count)
            for range in ranges {
                Self.hash(range.lowerBound, into: &hasher)
                Self.hash(range.upperBound, into: &hasher)
            }
        }
    }

    private static func hash(_ version: Version, into hasher: inout Hasher) {
        hasher.combine(version.major)
        hasher.combine(version.minor)
        hasher.combine(version.patch)
        // `Version.==` also stops at the first pair of differently spelled,
        // numerically equal identifiers and ignores what follows, so
        // `1.0.0-0.alpha == 1.0.0-00.beta`. Only the identifiers up to and
        // including the first numeric one, hashed by value, are therefore
        // common to every pair of equal versions; versions that differ only
        // after it, such as `1.0.0-beta.1.2` and `1.0.0-beta.1.3`, collide.
        for identifier in version.prereleaseIdentifiers {
            if let number = Int(identifier) {
                hasher.combine(0 as UInt8)
                hasher.combine(number)
                return
            }
            hasher.combine(1 as UInt8)
            hasher.combine(identifier)
        }
        hasher.combine(2 as UInt8)
    }
}

fileprivate extension VersionSetSpecifier {
    var ranges: [Range<Version>] {
        switch self {
        case .any:
            preconditionFailure("the universal set cannot be represented as finite ranges")
        case .empty:
            return []
        case .exact(let version):
            return [version.exactRange]
        case .range(let range):
            return [range]
        case .ranges(let ranges):
            return ranges
        }
    }

    var normalizedRanges: [Range<Version>] {
        Self.normalize(self.ranges)
    }

    var semanticSignature: FiniteVersionSet {
        FiniteVersionSet(
            releases: Self.normalizedProjections(self.ranges, using: \.releaseProjection),
            prereleases: Self.normalizedProjections(self.ranges, using: \.prereleaseProjection)
        )
    }

    static func normalize(_ ranges: [Range<Version>]) -> [Range<Version>] {
        let ranges = ranges
            .filter { $0.releaseProjection != nil || $0.prereleaseProjection != nil }
            .sorted(by: Self.areInIncreasingOrder)

        // Sort once and merge adjacent components with a stack. Equality and
        // hashing compare normalized projections, so there is no need for a
        // repeated all-pairs scan to remove semantically redundant overlaps.
        var result: [Range<Version>] = []
        for range in ranges {
            var candidate = range
            while let previous = result.last,
                  let merged = Self.mergeIfEquivalent(previous, candidate) {
                result.removeLast()
                candidate = merged
            }
            result.append(candidate)
        }
        return result
    }

    static func areInIncreasingOrder(_ lhs: Range<Version>, _ rhs: Range<Version>) -> Bool {
        if lhs.lowerBound == rhs.lowerBound {
            return lhs.upperBound < rhs.upperBound
        }
        return lhs.lowerBound < rhs.lowerBound
    }

    static func mergeIfEquivalent(_ lhs: Range<Version>, _ rhs: Range<Version>) -> Range<Version>? {
        guard lhs.lowerBound <= rhs.upperBound, rhs.lowerBound <= lhs.upperBound else {
            return nil
        }

        let merged = min(lhs.lowerBound, rhs.lowerBound)..<max(lhs.upperBound, rhs.upperBound)
        // `Range.contains(version:)` has separate admission rules for release
        // and prerelease versions. An ordinally contiguous merge is safe only
        // when it preserves both projections.
        guard
            Self.normalizedProjections([lhs, rhs], using: \.releaseProjection)
                == Self.normalizedProjections([merged], using: \.releaseProjection),
            Self.normalizedProjections([lhs, rhs], using: \.prereleaseProjection)
                == Self.normalizedProjections([merged], using: \.prereleaseProjection)
        else {
            return nil
        }
        return merged
    }

    static func normalizedProjections(
        _ ranges: [Range<Version>],
        using projection: (Range<Version>) -> Range<Version>?
    ) -> [Range<Version>] {
        let ranges = ranges.compactMap(projection).sorted(by: Self.areInIncreasingOrder)
        var result: [Range<Version>] = []
        for range in ranges {
            // The `max..<max` point (see `Version.exactRange`) touches every
            // range that ends at `max` without being contained in it, so it is
            // only merged with itself.
            if let last = result.last, range.lowerBound <= last.upperBound,
               !range.isMaximumReleasePoint || last.isMaximumReleasePoint {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    static func from(_ ranges: [Range<Version>]) -> VersionSetSpecifier {
        let ranges = Self.normalize(ranges)
        switch ranges.count {
        case 0:
            return .empty
        case 1:
            let range = ranges[0]
            if range.isExact {
                return .exact(range.lowerBound)
            }
            return .range(range)
        default:
            return .ranges(ranges)
        }
    }
}

extension VersionSetSpecifier {
    var isExact: Bool {
        switch self {
        case .any:
            return false
        default:
            let signature = self.semanticSignature
            if signature.prereleases.isEmpty,
               signature.releases.count == 1,
               signature.releases[0].isExact {
                return true
            }
            return signature.releases.isEmpty
                && signature.prereleases.count == 1
                && signature.prereleases[0].isExact
        }
    }
}

extension VersionSetSpecifier {
    public static func union(from range: Swift.Range<Version>) -> VersionSetSpecifier {
        return .union(from: [range])
    }

    public static func union(from ranges: [Swift.Range<Version>]) -> VersionSetSpecifier {
        Self.from(ranges)
    }

    public func union(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any), (.any, _):
            return .any
        default:
            return Self.from(self.normalizedRanges + rhs.normalizedRanges)
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
        default:
            let lhsRanges = self.normalizedRanges
            let rhsRanges = rhs.normalizedRanges
            var result: [Range<Version>] = []
            for lhsRange in lhsRanges {
                for rhsRange in rhsRanges {
                    result.append(contentsOf: Self.intersection(lhsRange, rhsRange))
                }
            }
            return Self.from(result)
        }
    }

    /// Intersect two ranges ordinally, on their raw bounds.
    ///
    /// Prerelease admission is a property of the bounds, not an independent
    /// dimension: `Range.contains(version:)` admits prereleases across the whole
    /// range as soon as *either* bound carries prerelease identifiers. Taking
    /// `max(lowerBound)..<min(upperBound)` therefore propagates an explicit
    /// prerelease opt-in from either operand into the result whenever that
    /// prerelease bound is the one that survives the clamping.
    ///
    /// Release membership of the result is exact, but prerelease membership is
    /// only an ordinal approximation that can err either way: it can admit
    /// prereleases that one operand rejects, and it can drop prereleases that
    /// both operands admit when neither surviving bound carries prerelease
    /// identifiers (`1.0.0-alpha..<2.0.0 ∩ 1.5.0..<3.0.0-beta` is
    /// `1.5.0..<2.0.0`, which drops `1.6.0-alpha`).
    ///
    /// That propagation is deliberate — it is how a release-only requirement
    /// such as `1.0.0..<2.0.0` coming from a transitive dependency still allows
    /// the prereleases that the root package opted into with `1.0.0-latest`.
    /// Intersecting the release and prerelease projections separately instead
    /// would make any release-only operand veto prereleases and break that
    /// inference.
    private static func intersection(
        _ lhs: Range<Version>,
        _ rhs: Range<Version>
    ) -> [Range<Version>] {
        // An exact requirement denotes one specific version, so it is
        // intersected by membership rather than by clamping bounds. This is
        // what stops the inference above from manufacturing a match for an
        // exact prerelease against a release-only range: pinning
        // `1.0.6-prerelease-1` is not enough to opt a plain `1.0.4..<2.0.0`
        // dependency into prereleases.
        if lhs.isExact {
            return rhs.contains(version: lhs.lowerBound) ? [lhs] : []
        }
        if rhs.isExact {
            return lhs.contains(version: rhs.lowerBound) ? [rhs] : []
        }

        let lowerBound = max(lhs.lowerBound, rhs.lowerBound)
        let upperBound = min(lhs.upperBound, rhs.upperBound)
        guard lowerBound < upperBound else { return [] }
        return [lowerBound..<upperBound]
    }
}

extension VersionSetSpecifier {
    public func difference(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (_, .any):
            return .empty
        case (.any, _):
            fatalError("\(#file):\(#line) - Illegal call of \(#function) on left hand side value of `.any`")
        default:
            var result = self.normalizedRanges
            for excluded in rhs.normalizedRanges {
                result = result.flatMap { Self.subtract(excluded, from: $0) }
            }
            return Self.from(result)
        }
    }

    private static func subtract(
        _ rhs: Range<Version>,
        from lhs: Range<Version>
    ) -> [Range<Version>] {
        if lhs.isExact {
            return rhs.contains(version: lhs.lowerBound) ? [] : [lhs]
        }
        if rhs.isExact {
            let version = rhs.lowerBound
            guard lhs.contains(version: version) else {
                return [lhs]
            }

            var result: [Range<Version>] = []
            // Keep the representable prereleases around a removed release.
            // What a positive union of the public Range-based cases cannot
            // express is keeping *all* prereleases that share the removed
            // release's core without the release itself, so those are
            // dropped; a subset such as `1.0.0-alpha..<1.0.0-beta` would be
            // representable on its own.
            let removesReleaseFromPrereleaseRange = lhs.supportsPrereleases && !version.supportsPrerelease
            let upperBound = removesReleaseFromPrereleaseRange
                ? version.prereleaseFloor
                : version
            if lhs.lowerBound < upperBound {
                result.append(lhs.lowerBound..<upperBound)
            }
            let successor = version.exactRange.upperBound
            let lowerBound = removesReleaseFromPrereleaseRange
                ? successor.prereleaseFloor
                : successor
            if lowerBound < lhs.upperBound {
                result.append(lowerBound..<lhs.upperBound)
            }
            return result
        }

        // A release-only `lhs` admits no prereleases, so only the releases of
        // `rhs` can be removed from it. Splitting on the raw bounds of `rhs`
        // would hand a prerelease bound to a remaining piece, which
        // `Range.contains(version:)` then reads as an opt-in to prereleases
        // that `lhs` never admitted.
        let excluded: Range<Version>
        if lhs.supportsPrereleases {
            excluded = rhs
        } else if let releases = rhs.releaseProjection {
            excluded = releases
        } else {
            return [lhs]
        }

        guard lhs.lowerBound < excluded.upperBound, excluded.lowerBound < lhs.upperBound else {
            return [lhs]
        }
        // Below a release upper bound, `lhs` admits no prerelease of that
        // release's core, so an overlap that starts at one removes nothing.
        // Splitting there anyway would end the remaining piece on that
        // prerelease and admit the prereleases of the core below it.
        if !lhs.upperBound.supportsPrerelease,
           excluded.lowerBound.withoutPrerelease == lhs.upperBound.withoutPrerelease {
            return [lhs]
        }

        var result: [Range<Version>] = []
        if lhs.lowerBound < excluded.lowerBound {
            result.append(lhs.lowerBound..<excluded.lowerBound)
        }
        if excluded.upperBound < lhs.upperBound {
            result.append(excluded.upperBound..<lhs.upperBound)
        }
        return result
    }
}

extension VersionSetSpecifier {
    /// Check if the set contains a version.
    public func contains(_ version: Version) -> Bool {
        switch self {
        case .empty:
            return false
        case .range(let range):
            return !range.isSemanticallyEmpty && range.contains(version: version)
        case .ranges(let ranges):
            return ranges.contains {
                !$0.isSemanticallyEmpty && $0.contains(version: version)
            }
        case .any:
            return true
        case .exact(let exact):
            return exact == version
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
            !range.isSemanticallyEmpty && range.supportsPrereleases
        case .ranges(let ranges):
            ranges.contains { !$0.isSemanticallyEmpty && $0.supportsPrereleases }
        }
    }

    package var withoutPrereleases: VersionSetSpecifier {
        if !supportsPrereleases {
            return self
        }

        return switch self {
        case .any:
            .any
        default:
            Self.from(self.normalizedRanges.map { range in
                if range.isExact {
                    return range.lowerBound.withoutPrerelease.exactRange
                }
                return range.withoutPrerelease
            })
        }
    }
}

extension VersionSetSpecifier: CustomStringConvertible {
    public var description: String {
        self.description(boundDescription: \.description)
    }

    /// `description` with range bounds as diagnostics print them; see
    /// `Version.diagnosticDescription`.
    var diagnosticDescription: String {
        self.description(boundDescription: \.diagnosticDescription)
    }

    private func description(boundDescription: (Version) -> String) -> String {
        switch self {
        case .any:
            return "any"
        default:
            let ranges = self.normalizedRanges.map {
                Self.description(of: $0, patchesUpperBound: self.isRange, boundDescription: boundDescription)
            }
            switch ranges.count {
            case 0:
                return "empty"
            case 1:
                return ranges[0]
            default:
                return "{" + ranges.joined(separator: ", ") + "}"
            }
        }
    }

    private var isRange: Bool {
        if case .range = self {
            return true
        }
        return false
    }

    private static func description(
        of range: Range<Version>,
        patchesUpperBound: Bool,
        boundDescription: (Version) -> String
    ) -> String {
        if range.isExact {
            return range.lowerBound.description
        }

        var upperBound = range.upperBound
        // Patch the version range representation. This shouldn't be
        // required once we have custom version range structure.
        if patchesUpperBound {
            if upperBound.major != .max && upperBound.minor == .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major + 1, 0, 0)
            }
            if upperBound.minor != .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major, upperBound.minor + 1, 0)
            }
        }
        return boundDescription(range.lowerBound) + "..<" + boundDescription(upperBound)
    }
}

extension Range where Bound == Version {
    /// Whether this is `exactRange` of its lower bound, i.e. the range that
    /// `VersionSetSpecifier.exact(lowerBound)` stands for.
    var isExact: Bool {
        // The identifiers are compared by spelling as well: `Version.==`
        // stops at the first pair of differently spelled but numerically
        // equal identifiers, so it would also accept an upper bound that
        // continues past such a pair and bounds more than one version.
        let exactRange = self.lowerBound.exactRange
        return self.upperBound == exactRange.upperBound
            && self.upperBound.prereleaseIdentifiers == exactRange.upperBound.prereleaseIdentifiers
    }
}

fileprivate extension Range where Bound == Version {
    var isSemanticallyEmpty: Bool {
        self.releaseProjection == nil && self.prereleaseProjection == nil
    }

    /// Whether this is `max..<max`, the encoding of
    /// `.exact(Version.maximumRelease)`; see `Version.exactRange`.
    var isMaximumReleasePoint: Bool {
        self.lowerBound == .maximumRelease && self.upperBound == .maximumRelease
    }

    var releaseProjection: Range<Version>? {
        // Checked on the raw bounds: an exact prerelease of the maximum
        // version must not project onto the maximum release.
        if self.isMaximumReleasePoint {
            return self
        }
        let lowerBound = self.lowerBound.withoutPrerelease
        let upperBound = self.upperBound.withoutPrerelease
        guard lowerBound < upperBound else {
            return nil
        }
        return lowerBound..<upperBound
    }

    var prereleaseProjection: Range<Version>? {
        guard self.supportsPrereleases else {
            return nil
        }

        let upperBound = self.upperBound.supportsPrerelease
            ? self.upperBound
            : self.upperBound.prereleaseFloor
        guard self.lowerBound < upperBound else {
            return nil
        }
        return self.lowerBound..<upperBound
    }

    var supportsPrereleases: Bool {
        self.lowerBound.supportsPrerelease || self.upperBound.supportsPrerelease
    }

    var withoutPrerelease: Range<Version> {
        Range(uncheckedBounds: (
            lower: self.lowerBound.withoutPrerelease,
            upper: self.upperBound.withoutPrerelease
        ))
    }
}

fileprivate extension Version {
    var supportsPrerelease: Bool {
        !self.prereleaseIdentifiers.isEmpty
    }

    /// The smallest prerelease of this version's core, which lies below every
    /// other prerelease of it.
    var prereleaseFloor: Version {
        Version(
            self.major,
            self.minor,
            self.patch,
            prereleaseIdentifiers: [Version.minimumPrereleaseIdentifier]
        )
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
