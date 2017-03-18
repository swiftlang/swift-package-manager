/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A struct representing semver version.
public struct Version {

    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int

    /// The pre-release identifier.
    public let prereleaseIdentifiers: [String]

    /// The build metadata.
    public let buildMetadataIdentifier: String?
    
    /// Create a version object.
    public init(
        _ major: Int,
        _ minor: Int,
        _ patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifier: String? = nil
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifier = buildMetadataIdentifier
    }
}

// MARK: Hashable

extension Version: Hashable {

    public static func ==(lhs: Version, rhs: Version) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers &&
               lhs.buildMetadataIdentifier == rhs.buildMetadataIdentifier
    }

    public var hashValue: Int {
        // FIXME: We need Swift hashing utilities; this is based on CityHash
        // inspired code inside the Swift stdlib.
        let mul: UInt64 = 0x9ddfea08eb382d69
        var result: UInt64 = 0
        result = (result &* mul) ^ UInt64(bitPattern: Int64(major.hashValue))
        result = (result &* mul) ^ UInt64(bitPattern: Int64(minor.hashValue))
        result = (result &* mul) ^ UInt64(bitPattern: Int64(patch.hashValue))
        result = prereleaseIdentifiers.reduce(result, { ($0 &* mul) ^ UInt64(bitPattern: Int64($1.hashValue)) })
        if let build = buildMetadataIdentifier {
            result = (result &* mul) ^ UInt64(bitPattern: Int64(build.hashValue))
        }
        return Int(truncatingBitPattern: result)
    }
}

// MARK: Comparable

extension Version: Comparable {

    public static func <(lhs: Version, rhs: Version) -> Bool {
        // FIXME: This method needs cleanup.
        let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
        let rhsComparators = [rhs.major, rhs.minor, rhs.patch]

        if lhsComparators != rhsComparators {
            return lhsComparators.lexicographicallyPrecedes(rhsComparators)
        }

        guard lhs.prereleaseIdentifiers.count > 0 else {
            // Non-prerelease lhs >= potentially prerelease rhs.
            return false
        }
        guard rhs.prereleaseIdentifiers.count > 0 else {
            // Prerelease lhs < non-prerelease rhs.
            return true
        }

        for (lhsPrereleaseIdentifier, rhsPrereleaseIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if lhsPrereleaseIdentifier == rhsPrereleaseIdentifier {
                continue
            }

            let typedLhsIdentifier: Any = Int(lhsPrereleaseIdentifier) ?? lhsPrereleaseIdentifier
            let typedRhsIdentifier: Any = Int(rhsPrereleaseIdentifier) ?? rhsPrereleaseIdentifier

            switch (typedLhsIdentifier, typedRhsIdentifier) {
                case let (int1 as Int, int2 as Int): return int1 < int2
                case let (string1 as String, string2 as String): return string1 < string2
                case (is Int, is String): return true // Int prereleases < String prereleases
                case (is String, is Int): return false
            default:
                return false
            }
        }
        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }
}

// MARK: CustomStringConvertible

extension Version: CustomStringConvertible {
    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if prereleaseIdentifiers.count > 0 {
            base += "-" + prereleaseIdentifiers.joined(separator: ".")
        }
        if let buildMetadataIdentifier = buildMetadataIdentifier {
            base += "+" + buildMetadataIdentifier
        }
        return base
    }
}
