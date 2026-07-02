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

import Foundation

/// Errors that can be thrown when parsing a ``PackageVersion`` from a
/// string.
public enum PackageVersionError: Error, Sendable, Equatable {
    /// The supplied string does not conform to the Semantic Versioning 2.0
    /// grammar used for package release version numbers.
    case invalidFormat
}

/// A Semantic Versioning (SemVer 2.0) package release version number.
///
/// The Swift Package Registry Service Specification (§2 *Conventions* and
/// §3.6 *Package identification*) defines a *version number* as an
/// identifier for a package release in accordance with the
/// [Semantic Versioning Specification][SemVer], and defines *precedence*
/// as the ordering of version numbers relative to each other per SemVer.
///
/// A value of this type represents the parsed components of a version
/// string of the form `MAJOR.MINOR.PATCH[-PRERELEASE][+BUILDMETADATA]`,
/// for example `1.2.3`, `2.0.0-beta.1`, or `1.0.0+build.42`.
///
/// The ``Comparable`` conformance implements SemVer precedence rules:
/// `MAJOR`, `MINOR`, and `PATCH` are compared numerically; a version
/// without a pre-release identifier has higher precedence than an
/// otherwise-equal version that has one; pre-release identifiers are
/// compared component-wise (numeric components numerically, alphanumeric
/// components lexicographically, with numeric components sorting below
/// alphanumeric ones); and build metadata is ignored for precedence.
///
/// [SemVer]: https://semver.org
public struct PackageVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The `MAJOR` component of the SemVer version.
    public let major: Int

    /// The `MINOR` component of the SemVer version.
    public let minor: Int

    /// The `PATCH` component of the SemVer version.
    public let patch: Int

    /// The optional pre-release identifier (the portion after `-` and
    /// before any `+`), or `nil` for a normal release. Its presence
    /// *lowers* precedence relative to an otherwise-equal version.
    public let prerelease: String?

    /// The optional build metadata (the portion after `+`), or `nil` if
    /// none was supplied. Build metadata is ignored when comparing
    /// versions.
    public let buildMetadata: String?

    /// Parses a SemVer 2.0 version string.
    ///
    /// The accepted grammar is:
    ///
    /// ```
    /// version        = numeric "." numeric "." numeric
    ///                  ["-" prerelease] ["+" buildmetadata]
    /// numeric        = "0" / positive-digit *digit
    /// prerelease     = ident *("." ident)
    /// buildmetadata  = ident *("." ident)
    /// ident          = 1*(ALPHA / DIGIT / "-")
    /// ```
    ///
    /// Numeric identifiers in the `MAJOR.MINOR.PATCH` triple and in
    /// pre-release components must not contain leading zeros.
    ///
    /// - Parameter raw: The raw version string to parse, for example
    ///   `"1.2.3"` or `"2.0.0-beta.1+exp.sha.5114f85"`.
    /// - Throws: ``PackageVersionError/invalidFormat`` if `raw` does not
    ///   match the SemVer grammar.
    public init(_ raw: String) throws {
        var rest = Substring(raw)
        var buildMetadata: String? = nil
        if let plus = rest.firstIndex(of: "+") {
            let build = rest[rest.index(after: plus)...]
            guard Self.isValidBuild(build) else { throw PackageVersionError.invalidFormat }
            buildMetadata = String(build)
            rest = rest[..<plus]
        }
        var prerelease: String? = nil
        if let dash = rest.firstIndex(of: "-") {
            let pre = rest[rest.index(after: dash)...]
            guard Self.isValidPrerelease(pre) else { throw PackageVersionError.invalidFormat }
            prerelease = String(pre)
            rest = rest[..<dash]
        }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Self.parseNumeric(parts[0]),
              let minor = Self.parseNumeric(parts[1]),
              let patch = Self.parseNumeric(parts[2])
        else { throw PackageVersionError.invalidFormat }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    /// The canonical SemVer string representation, reconstructed from the
    /// parsed components: `MAJOR.MINOR.PATCH[-PRERELEASE][+BUILDMETADATA]`.
    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if let prerelease { s += "-\(prerelease)" }
        if let buildMetadata { s += "+\(buildMetadata)" }
        return s
    }

    /// A string whose lexicographic ordering within a given major/minor/patch
    /// triple reflects SemVer *precedence*, omitting build metadata.
    ///
    /// Two versions that differ only in ``buildMetadata`` produce the same
    /// ``precedenceKey``, matching the SemVer rule that build metadata is
    /// ignored when determining precedence.
    public var precedenceKey: String {
        var s = "\(major).\(minor).\(patch)"
        if let prerelease { s += "-\(prerelease)" }
        return s
    }

    /// Orders two versions by SemVer precedence.
    ///
    /// `MAJOR`, `MINOR`, and `PATCH` are compared numerically in order. If
    /// those are all equal, a version without a pre-release identifier has
    /// *higher* precedence than one with a pre-release identifier.
    /// Pre-release identifiers themselves are compared component-wise:
    /// numeric components numerically, alphanumeric components
    /// lexicographically, with numeric components sorting below
    /// alphanumeric ones; a shorter set of components sorts below a longer
    /// one when every shared component is equal. Build metadata is ignored.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand version.
    ///   - rhs: The right-hand version.
    /// - Returns: `true` if `lhs` has lower SemVer precedence than `rhs`.
    public static func < (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        case let (l?, r?): return comparePrerelease(l, r) == .orderedAscending
        }
    }

    private static func parseNumeric(_ s: Substring) -> Int? {
        guard !s.isEmpty else { return nil }
        if s.count > 1 && s.first == "0" { return nil }
        guard s.allSatisfy(\.isNumber) else { return nil }
        return Int(s)
    }

    private static func isValidPrerelease(_ s: Substring) -> Bool {
        guard !s.isEmpty else { return false }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            guard !part.isEmpty else { return false }
            if part.allSatisfy(\.isNumber) {
                return !(part.count > 1 && part.first == "0")
            }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private static func isValidBuild(_ s: Substring) -> Bool {
        guard !s.isEmpty else { return false }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private static func comparePrerelease(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".")
        let bParts = b.split(separator: ".")
        for (x, y) in zip(aParts, bParts) {
            let xi = Int(x)
            let yi = Int(y)
            if let xi, let yi {
                if xi != yi { return xi < yi ? .orderedAscending : .orderedDescending }
            } else if xi != nil {
                return .orderedAscending
            } else if yi != nil {
                return .orderedDescending
            } else if x != y {
                return x < y ? .orderedAscending : .orderedDescending
            }
        }
        if aParts.count != bParts.count {
            return aParts.count < bParts.count ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
}
