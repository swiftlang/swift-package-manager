//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCUtility.Version

extension OSVRecord {
    /// The ecosystem identifier used for SwiftPM packages in OSV.
    static let swiftEcosystem = "SwiftURL"

    /// Returns whether `version` falls into any affected range or explicit version list.
    ///
    /// When `packageName` is `nil`, every `affected` entry is considered (registry records);
    /// otherwise only `SwiftURL` entries with a matching package name are.
    public func affects(_ version: Version, packageName: String?) -> Bool {
        for entry in self.matchingEntries(packageName: packageName) {
            if (entry.versions ?? []).contains(where: { Version($0) == version }) {
                return true
            }
            for range in entry.semverRanges where range.intervals.contains(where: { $0.lowerBound <= version && version < $0.upperBound }) {
                return true
            }
        }
        return false
    }

    /// Every `fixed` version greater than `version` across all matching `SEMVER` ranges, ascending.
    ///
    /// Precondition: meant to be called for a version that `affects` returns true for;
    /// it does not check that `version` is itself vulnerable.
    public func fixedVersions(after version: Version, packageName: String?) -> [Version] {
        self.fixedVersions(packageName: packageName).filter { $0 > version }
    }

    /// Every `fixed` version across all matching `SEMVER` ranges, ascending and without duplicates.
    ///
    /// Used for packages pinned to a revision, where no pinned version tells which fixes are newer.
    public func fixedVersions(packageName: String?) -> [Version] {
        var result = Set<Version>()
        for entry in self.matchingEntries(packageName: packageName) {
            for range in entry.semverRanges {
                for event in range.events {
                    if let fixed = event.fixed.flatMap({ Version($0) }) {
                        result.insert(fixed)
                    }
                }
            }
        }
        return result.sorted()
    }

    /// The vulnerable intervals of all matching `SEMVER` ranges, in declaration order.
    /// An inclusive upper bound (`last_affected`) is represented by the next possible version.
    func vulnerableRanges(packageName: String?) -> [Swift.Range<Version>] {
        self.matchingEntries(packageName: packageName)
            .flatMap(\.semverRanges)
            .flatMap(\.intervals)
    }

    private func matchingEntries(packageName: String?) -> [Affected] {
        (self.affected ?? []).filter { entry in
            guard let packageName else { return true }
            guard let package = entry.package else { return false }
            return package.ecosystem == Self.swiftEcosystem && package.name == packageName
        }
    }
}

extension OSVRecord.Affected {
    fileprivate var semverRanges: [OSVRecord.Range] {
        (self.ranges ?? []).filter { $0.type == "SEMVER" }
    }
}

extension OSVRecord.Range {
    /// Lowest possible version, used for `introduced: "0"`.
    private static let lowest = Version(0, 0, 0, prereleaseIdentifiers: ["0"])
    /// Upper bound for intervals that are never closed.
    private static let highest = Version(Int.max, Int.max, Int.max)

    /// Evaluates the events in order per the OSV specification.
    fileprivate var intervals: [Swift.Range<Version>] {
        let limit = self.events.lazy.compactMap { $0.limit.flatMap { Version($0) } }.first
        var result: [Swift.Range<Version>] = []
        var start: Version?

        func close(at end: Version) {
            if let lower = start, lower < end {
                result.append(lower ..< end)
            }
            start = nil
        }

        for event in self.events {
            if let introduced = event.introduced {
                let parsed = introduced == "0" ? Self.lowest : Version(introduced)
                if start == nil, let parsed { start = parsed }
            } else if let fixed = event.fixed.flatMap({ Version($0) }) {
                close(at: fixed)
            } else if let last = event.lastAffected.flatMap({ Version($0) }) {
                close(at: last.successor)
            }
        }
        close(at: Self.highest)

        guard let limit else { return result }
        return result.compactMap { interval in
            guard interval.lowerBound < limit else { return nil }
            return interval.lowerBound ..< min(interval.upperBound, limit)
        }
    }
}

extension Version {
    /// The smallest version strictly greater than `self`.
    fileprivate var successor: Version {
        if self.prereleaseIdentifiers.isEmpty {
            return Version(self.major, self.minor, self.patch + 1, prereleaseIdentifiers: ["0"])
        }
        return Version(
            self.major, self.minor, self.patch,
            prereleaseIdentifiers: self.prereleaseIdentifiers + ["0"]
        )
    }
}
