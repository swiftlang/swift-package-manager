//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCUtility.Version

extension Version {
    /// The next patch version of a release, or for a prerelease the version
    /// with a `"0"` identifier appended.
    ///
    /// The prerelease form is not the immediate successor, since numeric
    /// identifiers may be negative; `exactRange` models an exact prerelease.
    ///
    /// A component at `Int.max` carries into the next-more-significant one
    /// instead of overflowing. `Version(.max, .max, .max)` has no successor;
    /// `VersionSetSpecifier` goes through `exactRange` and never asks for it.
    ///
    /// For release versions the successor is the next patch version, and the
    /// range `self..<self.nextPatch()` denotes exactly `self`: no release
    /// version lies strictly between the two, and a range whose bounds carry
    /// no prerelease identifiers admits no prerelease versions at all.
    func nextPatch() -> Version {
        if self.prereleaseIdentifiers.isEmpty {
            if self.patch < .max {
                return Version(self.major, self.minor, self.patch + 1)
            } else if self.minor < .max {
                return Version(self.major, self.minor + 1, 0)
            } else if self.major < .max {
                return Version(self.major + 1, 0, 0)
            } else {
                preconditionFailure("the maximum representable version has no successor")
            }
        } else {
            return Version(self.major, self.minor, self.patch, prereleaseIdentifiers: self.prereleaseIdentifiers + ["0"])
        }
    }

    /// The maximum representable release version, which has no successor.
    static var maximumRelease: Version { Version(.max, .max, .max) }

    /// The smallest prerelease identifier under `Version`'s ordering.
    ///
    /// Identifiers that parse as `Int` compare numerically, negative values
    /// included, and before every non-numeric identifier, so `"0"` is not the
    /// minimum: `1.0.0-alpha.-1 < 1.0.0-alpha.0`.
    static let minimumPrereleaseIdentifier = String(Int.min)

    /// The half-open range that `VersionSetSpecifier.exact(self)` stands for.
    ///
    /// For a release this is `self..<self.nextPatch()`. For a prerelease the
    /// upper bound appends `minimumPrereleaseIdentifier` rather than the
    /// `"0"` that `nextPatch()` appends, because `self..<self.nextPatch()`
    /// would also contain versions such as `1.0.0-alpha.-1`.
    /// `Version.maximumRelease` has no successor, so it is encoded as the
    /// zero-width range `self..<self` instead. That range is the one
    /// zero-width range that denotes a version rather than the empty set;
    /// `Range.contains(version:)` already admits it through its
    /// `lowerBound == version` special case.
    var exactRange: Range<Version> {
        if self == .maximumRelease {
            return self..<self
        }
        if self.prereleaseIdentifiers.isEmpty {
            return self..<self.nextPatch()
        }
        return self..<Version(
            self.major,
            self.minor,
            self.patch,
            prereleaseIdentifiers: self.prereleaseIdentifiers + [Self.minimumPrereleaseIdentifier]
        )
    }

    /// This version as diagnostics print it.
    ///
    /// Range bounds derived from `exactRange` end in
    /// `minimumPrereleaseIdentifier`, which diagnostics spell `0` as
    /// `nextPatch()` does. The printed and actual bounds differ only for
    /// negative numeric prerelease identifiers.
    var diagnosticDescription: String {
        guard self.prereleaseIdentifiers.last == Self.minimumPrereleaseIdentifier else {
            return self.description
        }
        return Version(
            self.major,
            self.minor,
            self.patch,
            prereleaseIdentifiers: self.prereleaseIdentifiers.dropLast() + ["0"],
            buildMetadataIdentifiers: self.buildMetadataIdentifiers
        ).description
    }
}
