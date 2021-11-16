/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2018 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// A version according to the semantic versioning specification.
///
/// A package version is a three period-separated integer, for example `1.0.0`. It must conform to the semantic versioning standard in order to ensure
/// that your package behaves in a predictable manner once developers update their
/// package dependency to a newer version. To achieve predictability, the semantic versioning specification proposes a set of rules and
/// requirements that dictate how version numbers are assigned and incremented. To learn more about the semantic versioning specification, visit
/// [semver.org](www.semver.org).
/// 
/// **The Major Version**
///
/// The first digit of a version, or  *major version*, signifies breaking changes to the API that require
/// updates to existing clients. For example, the semantic versioning specification
/// considers renaming an existing type, removing a method, or changing a method's signature
/// breaking changes. This also includes any backward-incompatible bug fixes or
/// behavioral changes of the existing API.
///
/// **The Minor Version**
///
/// Update the second digit of a version, or *minor version*, if you add functionality in a backward-compatible manner.
/// For example, the semantic versioning specification considers adding a new method
/// or type without changing any other API to be backward-compatible.
///
/// **The Patch Version**
///
/// Increase the third digit of a version, or *patch version*, if you are making a backward-compatible bug fix.
/// This allows clients to benefit from bugfixes to your package without incurring
/// any maintenance burden.
public struct Version {
    
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
    public init(
        _ major: Int,
        _ minor: Int,
        _ patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifiers: [String] = []
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }
}

extension Version: Comparable {
    // Although `Comparable` inherits from `Equatable`, it does not provide a new default implementation of `==`, but instead uses `Equatable`'s default synthesised implementation. The compiler-synthesised `==`` is composed of [member-wise comparisons](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md#implementation-details), which leads to a false `false` when 2 semantic versions differ by only their build metadata identifiers, contradicting SemVer 2.0.0's [comparison rules](https://semver.org/#spec-item-10).
    @inlinable
    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(lhs > rhs)
    }
    
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
            
            if let lhsNumericPrereleaseIdentifier = lhsNumericPrereleaseIdentifier,
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
