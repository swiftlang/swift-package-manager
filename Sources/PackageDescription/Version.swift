//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A version according to the semantic versioning specification.
///
/// A package version consists of three integers separated by periods, for example `1.0.0`. It must conform to the semantic versioning standard in order to ensure
/// that your package behaves in a predictable manner once developers update their
/// package dependency to a newer version. To achieve predictability, the semantic versioning specification proposes a set of rules and
/// requirements that dictate how version numbers are assigned and incremented. To learn more about the semantic versioning specification, visit
/// [Semantic Versioning 2.0.0](https://semver.org).
///
/// - term The major version: The first digit of a version, or _major version_,
/// signifies breaking changes to the API that require updates to existing
/// clients. For example, the semantic versioning specification considers
/// renaming an existing type, removing a method, or changing a method's
/// signature breaking changes. This also includes any backward-incompatible bug
/// fixes or behavioral changes of the existing API.
///
/// - term The minor version:
/// Update the second digit of a version, or _minor version_, if you add
/// functionality in a backward-compatible manner. For example, the semantic
/// versioning specification considers adding a new method or type without
/// changing any other API to be backward-compatible.
///
/// - term The patch version:
/// Increase the third digit of a version, or _patch version_, if you're making
/// a backward-compatible bug fix. This allows clients to benefit from bugfixes
/// to your package without incurring any maintenance burden.
public struct Version: Sendable {

    /// The major version according to the semantic versioning standard.
    public let major: Int

    /// The minor version according to the semantic versioning standard.
    public let minor: Int

    /// The patch version according to the semantic versioning standard.
    public let patch: Int

    /// The pre-release identifier according to the semantic versioning standard, such as `-beta.1`.
    public let prereleaseIdentifiers: [String]

    /// The build metadata of this version according to the semantic versioning standard, such as a commit hash.
    public let buildMetadataIdentifiers: [String]

    /// Initializes a version struct with the provided components of a semantic version.
    ///
    /// - Parameters:
    ///   - major: The major version number.
    ///   - minor: The minor version number.
    ///   - patch: The patch version number.
    ///   - prereleaseIdentifiers: The pre-release identifier.
    ///   - buildMetaDataIdentifiers: Build metadata that identifies a build.
    ///
    /// - Precondition: `major >= 0 && minor >= 0 && patch >= 0`.
    /// - Precondition: `prereleaseIdentifiers` can contain only ASCII alpha-numeric characters and "-".
    /// - Precondition: `buildMetaDataIdentifiers` can contain only ASCII alpha-numeric characters and "-".
    public init(
        _ major: Int,
        _ minor: Int,
        _ patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifiers: [String] = []
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
        precondition(
            prereleaseIdentifiers.allSatisfy {
                $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            },
            #"Pre-release identifiers can contain only ASCII alpha-numeric characters and "-"."#
        )
        precondition(
            buildMetadataIdentifiers.allSatisfy {
                $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            },
            #"Build metadata identifiers can contain only ASCII alpha-numeric characters and "-"."#
        )
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }
}

extension Version: Comparable {
    // Although `Comparable` inherits from `Equatable`, it does not provide a new default implementation of `==`, but instead uses `Equatable`'s default synthesised implementation. The compiler-synthesised `==`` is composed of [member-wise comparisons](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md#implementation-details), which leads to a false `false` when 2 semantic versions differ by only their build metadata identifiers, contradicting SemVer 2.0.0's [comparison rules](https://semver.org/#spec-item-10).
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`, `a ==
    /// b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    ///
    /// - Returns: A boolean value indicating the result of the equality test.
    @inlinable
    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(lhs > rhs)
    }
    
    /// Returns a Boolean value indicating whether the value of the first
    /// argument is less than that of the second argument.
    ///
    /// The precedence is determined according to rules described in the [Semantic Versioning 2.0.0](https://semver.org) standard, paragraph 11.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func < (lhs: Version, rhs: Version) -> Bool {
        let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
        let rhsComparators = [rhs.major, rhs.minor, rhs.patch]

        if lhsComparators != rhsComparators {
            return lhsComparators.lexicographicallyPrecedes(rhsComparators)
        }

        guard lhs.prereleaseIdentifiers.count > 0 else {
            return false // Non-prerelease lhs >= potentially prerelease rhs
        }

        guard rhs.prereleaseIdentifiers.count > 0 else {
            return true // Prerelease lhs < non-prerelease rhs
        }

        for (lhsPrereleaseIdentifier, rhsPrereleaseIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if lhsPrereleaseIdentifier == rhsPrereleaseIdentifier {
                continue
            }

            // Check if either of the 2 pre-release identifiers is numeric.
            let lhsNumericPrereleaseIdentifier = Int(lhsPrereleaseIdentifier)
            let rhsNumericPrereleaseIdentifier = Int(rhsPrereleaseIdentifier)

            if let lhsNumericPrereleaseIdentifier,
               let rhsNumericPrereleaseIdentifier = rhsNumericPrereleaseIdentifier {
                return lhsNumericPrereleaseIdentifier < rhsNumericPrereleaseIdentifier
            } else if lhsNumericPrereleaseIdentifier != nil {
                return true // numeric pre-release < non-numeric pre-release
            } else if rhsNumericPrereleaseIdentifier != nil {
                return false // non-numeric pre-release > numeric pre-release
            } else {
                return lhsPrereleaseIdentifier < rhsPrereleaseIdentifier
            }
        }

        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }
}

extension Version: CustomStringConvertible {
    /// A textual description of the version object.
    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            base += "-" + prereleaseIdentifiers.joined(separator: ".")
        }
        if !buildMetadataIdentifiers.isEmpty {
            base += "+" + buildMetadataIdentifiers.joined(separator: ".")
        }
        return base
    }
}
