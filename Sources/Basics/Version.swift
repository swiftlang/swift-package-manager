/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// A struct representing a semver version.
public struct Version: Sendable {

    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int

    /// The pre-release identifier.
    public let prereleaseIdentifiers: [String]

    /// The build metadata.
    public let buildMetadataIdentifiers: [String]

    /// Creates a version object.
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

/// An error that occurs during the creation of a version.
public enum VersionError: Error, CustomStringConvertible {
    /// The version string contains non-ASCII characters.
    /// - Parameter versionString: The version string.
    case nonASCIIVersionString(_ versionString: String)
    /// The version core contains an invalid number of Identifiers.
    /// - Parameters:
    ///   - identifiers: The version core identifiers in the version string.
    ///   - usesLenientParsing: A Boolean value indicating whether or not the lenient parsing mode was enabled when this error occurred.
    case invalidVersionCoreIdentifiersCount(_ identifiers: [String], usesLenientParsing: Bool)
    /// Some or all of the version core identifiers contain non-numerical characters or are empty.
    /// - Parameter identifiers: The version core identifiers in the version string.
    case nonNumericalOrEmptyVersionCoreIdentifiers(_ identifiers: [String])
    /// Some or all of the pre-release identifiers contain characters other than alpha-numerics and hyphens.
    /// - Parameter identifiers: The pre-release identifiers in the version string.
    case nonAlphaNumerHyphenalPrereleaseIdentifiers(_ identifiers: [String])
    /// Some or all of the build metadata identifiers contain characters other than alpha-numerics and hyphens.
    /// - Parameter identifiers: The build metadata identifiers in the version string.
    case nonAlphaNumerHyphenalBuildMetadataIdentifiers(_ identifiers: [String])

    public var description: String {
        switch self {
        case let .nonASCIIVersionString(versionString):
            return "non-ASCII characters in version string '\(versionString)'"
        case let .invalidVersionCoreIdentifiersCount(identifiers, usesLenientParsing):
            return "\(identifiers.count > 3 ? "more than 3" : "fewer than \(usesLenientParsing ? 2 : 3)") identifiers in version core '\(identifiers.joined(separator: "."))'"
        case let .nonNumericalOrEmptyVersionCoreIdentifiers(identifiers):
            if !identifiers.allSatisfy( { !$0.isEmpty } ) {
                return "empty identifiers in version core '\(identifiers.joined(separator: "."))'"
            } else {
                // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
                let nonNumericalIdentifiers = identifiers.filter { !$0.allSatisfy(\.isNumber) }
                return "non-numerical characters in version core identifier\(nonNumericalIdentifiers.count > 1 ? "s" : "") \(nonNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
            }
        case let .nonAlphaNumerHyphenalPrereleaseIdentifiers(identifiers):
            // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
            let nonAlphaNumericalIdentifiers = identifiers.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
            return "characters other than alpha-numerics and hyphens in pre-release identifier\(nonAlphaNumericalIdentifiers.count > 1 ? "s" : "") \(nonAlphaNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
        case let .nonAlphaNumerHyphenalBuildMetadataIdentifiers(identifiers):
            // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
            let nonAlphaNumericalIdentifiers = identifiers.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
            return "characters other than alpha-numerics and hyphens in build metadata identifier\(nonAlphaNumericalIdentifiers.count > 1 ? "s" : "") \(nonAlphaNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
        }
    }
}

extension Version {
    // TODO: Rename this function to `init(string:usesLenientParsing:) throws`, after `init?(string: String)` is removed.
    // TODO: Find a better error-checking order.
    // Currently, if a version string is "forty-two", this initializer throws an error that says "forty" is only 1 version core identifier, which is not enough.
    // But this is misleading the user to consider "forty" as a valid version core identifier.
    // We should find a way to check for (or throw) "wrong characters used" errors first, but without overly-complicating the logic.
    /// Creates a version from the given string.
    /// - Parameters:
    ///   - versionString: The string to create the version from.
    ///   - usesLenientParsing: A Boolean value indicating whether or not the version string should be parsed leniently. If `true`, then the patch version is assumed to be `0` if it's not provided in the version string; otherwise, the parsing strictly follows the Semantic Versioning 2.0.0 rules. This value defaults to `false`.
    /// - Throws: A `VersionError` instance if the `versionString` doesn't follow [SemVer 2.0.0](https://semver.org).
    public init(versionString: String, usesLenientParsing: Bool = false) throws {
        // SemVer 2.0.0 allows only ASCII alphanumerical characters and "-" in the version string, except for "." and "+" as delimiters. ("-" is used as a delimiter between the version core and pre-release identifiers, but it's allowed within pre-release and metadata identifiers as well.)
        // Alphanumerics check will come later, after each identifier is split out (i.e. after the delimiters are removed).
        guard versionString.allSatisfy(\.isASCII) else {
            throw VersionError.nonASCIIVersionString(versionString)
        }

        let metadataDelimiterIndex = versionString.firstIndex(of: "+")
        // SemVer 2.0.0 requires that pre-release identifiers come before build metadata identifiers
        let prereleaseDelimiterIndex = versionString[..<(metadataDelimiterIndex ?? versionString.endIndex)].firstIndex(of: "-")

        let versionCore = versionString[..<(prereleaseDelimiterIndex ?? metadataDelimiterIndex ?? versionString.endIndex)]
        let versionCoreIdentifiers = versionCore.split(separator: ".", omittingEmptySubsequences: false)

        guard versionCoreIdentifiers.count == 3 || (usesLenientParsing && versionCoreIdentifiers.count == 2) else {
            throw VersionError.invalidVersionCoreIdentifiersCount(versionCoreIdentifiers.map { String($0) }, usesLenientParsing: usesLenientParsing)
        }

        guard
            // Major, minor, and patch versions must be ASCII numbers, according to the semantic versioning standard.
            // Converting each identifier from a substring to an integer doubles as checking if the identifiers have non-numeric characters.
            let major = Int(versionCoreIdentifiers[0]),
            let minor = Int(versionCoreIdentifiers[1]),
            let patch = usesLenientParsing && versionCoreIdentifiers.count == 2 ? 0 : Int(versionCoreIdentifiers[2])
        else {
            throw VersionError.nonNumericalOrEmptyVersionCoreIdentifiers(versionCoreIdentifiers.map { String($0) })
        }

        self.major = major
        self.minor = minor
        self.patch = patch

        if let prereleaseDelimiterIndex = prereleaseDelimiterIndex {
            let prereleaseStartIndex = versionString.index(after: prereleaseDelimiterIndex)
            let prereleaseIdentifiers = versionString[prereleaseStartIndex..<(metadataDelimiterIndex ?? versionString.endIndex)].split(separator: ".", omittingEmptySubsequences: false)
            guard prereleaseIdentifiers.allSatisfy( { $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) } ) else {
                throw VersionError.nonAlphaNumerHyphenalPrereleaseIdentifiers(prereleaseIdentifiers.map { String($0) })
            }
            self.prereleaseIdentifiers = prereleaseIdentifiers.map { String($0) }
        } else {
            self.prereleaseIdentifiers = []
        }

        if let metadataDelimiterIndex = metadataDelimiterIndex {
            let metadataStartIndex = versionString.index(after: metadataDelimiterIndex)
            let buildMetadataIdentifiers = versionString[metadataStartIndex...].split(separator: ".", omittingEmptySubsequences: false)
            guard buildMetadataIdentifiers.allSatisfy( { $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) } ) else {
                throw VersionError.nonAlphaNumerHyphenalBuildMetadataIdentifiers(buildMetadataIdentifiers.map { String($0) })
            }
            self.buildMetadataIdentifiers = buildMetadataIdentifiers.map { String($0) }
        } else {
            self.buildMetadataIdentifiers = []
        }
    }
}

extension Version: Comparable, Hashable {

    func isEqualWithoutPrerelease(_ other: Version) -> Bool {
        return major == other.major && minor == other.minor && patch == other.patch
    }

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

    // Custom `Equatable` conformance leads to custom `Hashable` conformance.
    // [SR-11588](https://bugs.swift.org/browse/SR-11588)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prereleaseIdentifiers)
    }
}

extension Version: CustomStringConvertible {
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

extension Version: LosslessStringConvertible {
    /// Initializes a version struct with the provided version string.
    /// - Parameter version: A version string to use for creating a new version struct.
    public init?(_ versionString: String) {
        try? self.init(versionString: versionString)
    }
}

extension Version {
    // This initialiser is no longer necessary, but kept around for source compatibility with SwiftPM.
    /// Create a version object from string.
    /// - Parameter  string: The string to parse.
    @available(*, deprecated, renamed: "init(_:)")
    public init?(string: String) {
        self.init(string)
    }
}

extension Version: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        guard let version = Version(value) else {
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

extension Version: JSONMappable, JSONSerializable {
    public init(json: JSON) throws {
        guard case .string(let string) = json else {
            throw JSON.MapError.custom(key: nil, message: "expected string, got \(json)")
        }
        guard let version = Version(string) else {
            throw JSON.MapError.custom(key: nil, message: "Invalid version string \(string)")
        }
        self.init(version)
    }

    public func toJSON() -> JSON {
        return .string(description)
    }

    init(_ version: Version) {
        self.init(
            version.major, version.minor, version.patch,
            prereleaseIdentifiers: version.prereleaseIdentifiers,
            buildMetadataIdentifiers: version.buildMetadataIdentifiers
        )
    }
}

extension Version: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        guard let version = Version(string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid version string \(string)"))
        }

        self.init(version)
    }
}

// MARK:- Range operations

extension ClosedRange where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}

// Disabled because compiler hits an assertion https://bugs.swift.org/browse/SR-5014
#if false
extension CountableRange where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}
#endif

extension Range where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}

extension Range where Bound == Version {
    public func contains(version: Version) -> Bool {
        // Special cases if version contains prerelease identifiers.
        if !version.prereleaseIdentifiers.isEmpty {
            // If the range does not contain prerelease identifiers, return false.
            if lowerBound.prereleaseIdentifiers.isEmpty && upperBound.prereleaseIdentifiers.isEmpty {
                return false
            }

            // At this point, one of the bounds contains prerelease identifiers.
            //
            // Reject 2.0.0-alpha when upper bound is 2.0.0.
            if upperBound.prereleaseIdentifiers.isEmpty && upperBound.isEqualWithoutPrerelease(version) {
                return false
            }
        }

        if lowerBound == version {
            return true
        }

        // Otherwise, apply normal contains rules.
        return version >= lowerBound && version < upperBound
    }
}
