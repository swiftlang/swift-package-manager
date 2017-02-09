/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A struct representing a semver version.
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

extension Version: Hashable {

    static public func ==(lhs: Version, rhs: Version) -> Bool {
        if lhs.major == rhs.major && 
           lhs.minor == rhs.minor && 
           lhs.patch == rhs.patch &&
           lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers &&
           lhs.buildMetadataIdentifier == rhs.buildMetadataIdentifier {
            return true
        }
        return false
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

extension Version: Comparable {

    public static func <(lhs: Version, rhs: Version) -> Bool {
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

public extension Version {

    /// Create a version object from string.
    ///
    /// - Parameters:
    ///   - string: The string to parse.
    init?(string: String) {
        let characters = string.characters
        let prereleaseStartIndex = characters.index(of: "-")
        let metadataStartIndex = characters.index(of: "+")

        let requiredEndIndex = prereleaseStartIndex ?? metadataStartIndex ?? characters.endIndex
        let requiredCharacters = characters.prefix(upTo: requiredEndIndex)
        let requiredComponents = requiredCharacters.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init).flatMap{ Int($0) }.filter{ $0 >= 0 }

        guard requiredComponents.count == 3 else {
            return nil
        }

        self.major = requiredComponents[0]
        self.minor = requiredComponents[1]
        self.patch = requiredComponents[2]

        if let prereleaseStartIndex = prereleaseStartIndex {
            let prereleaseEndIndex = metadataStartIndex ?? characters.endIndex
            let prereleaseCharacters = characters[characters.index(after: prereleaseStartIndex)..<prereleaseEndIndex]
            prereleaseIdentifiers = prereleaseCharacters.split(separator: ".").map{ String($0) }
        } else {
            prereleaseIdentifiers = []
        }

        var buildMetadataIdentifier: String? = nil
        if let metadataStartIndex = metadataStartIndex {
            let buildMetadataCharacters = characters.suffix(from: characters.index(after: metadataStartIndex))
            if !buildMetadataCharacters.isEmpty {
                buildMetadataIdentifier = String(buildMetadataCharacters)
            }
        }
        self.buildMetadataIdentifier = buildMetadataIdentifier
    }
}

extension Version: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        guard let version = Version(string: value) else {
            fatalError("\(value) is not a valid version")
        }
        self = version
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}
