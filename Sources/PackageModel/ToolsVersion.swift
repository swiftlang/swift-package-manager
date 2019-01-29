/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

import Foundation
import SPMUtility

/// Tools version represents version of the Swift toolchain.
public struct ToolsVersion: CustomStringConvertible, Comparable, Hashable {

    public static let v3 = ToolsVersion(version: "3.1.0")
    public static let v4 = ToolsVersion(version: "4.0.0")
    public static let v5 = ToolsVersion(version: "5.0.0")

    /// The current tools version in use.
    public static let currentToolsVersion = ToolsVersion(string:
        "\(Versioning.currentVersion.major)." +
        "\(Versioning.currentVersion.minor)." +
        "\(Versioning.currentVersion.patch)")!

    /// The minimum tools version that is required by the package manager.
    public static let minimumRequired: ToolsVersion = .v4

    /// Regex pattern to parse tools version. The format is SemVer 2.0 with an
    /// addition that specifying the patch version is optional.
    static let toolsVersionRegex = try! NSRegularExpression(pattern: "^" +
        "(\\d+)\\.(\\d+)(?:\\.(\\d+))?" +
        "(" +
            "\\-[A-Za-z\\d]+(?:\\.[A-Za-z\\d]+)*" +
        ")?" +
        "(" +
            "\\+[A-Za-z\\d]+(?:\\.[A-Za-z\\d]+)*" +
        ")?$", options: [])

    /// The major version number.
    public var major: Int {
        return _version.major
    }

    /// The minor version number.
    public var minor: Int {
        return _version.minor
    }

    /// The patch version number.
    public var patch: Int {
        return _version.patch
    }

    /// The underlying backing store.
    fileprivate let _version: Version

    /// Create an instance of tools version from a given string.
    public init?(string: String) {
        guard let match = ToolsVersion.toolsVersionRegex.firstMatch(
            in: string, options: [], range: NSRange(location: 0, length: string.count)) else {
            return nil
        }
        // The regex succeeded, compute individual components.
        assert(match.numberOfRanges == 6)
        let string = NSString(string: string)
        let major = Int(string.substring(with: match.range(at: 1)))!
        let minor = Int(string.substring(with: match.range(at: 2)))!
        let patchRange = match.range(at: 3)
        let patch = patchRange.location != NSNotFound ? Int(string.substring(with: patchRange))! : 0
        // We ignore storing pre-release and build identifiers for now.
        _version = Version(major, minor, patch)
    }

    /// Create instance of tools version from a given version.
    ///
    /// - precondition: prereleaseIdentifiers and buildMetadataIdentifier should not be present.
    public init(version: Version) {
        _version = version
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        return _version.description
    }

    // MARK: - Comparable

    public static func < (lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }
}

/// Represents a Swift language version.
public struct SwiftLanguageVersion: CustomStringConvertible, Comparable {

    /// Swift language version 3.
    public static let v3 = SwiftLanguageVersion(uncheckedString: "3")

    /// Swift language version 4.
    public static let v4 = SwiftLanguageVersion(uncheckedString: "4")

    /// Swift language version 4.2.
    public static let v4_2 = SwiftLanguageVersion(uncheckedString: "4.2")

    /// Swift language version 5.
    public static let v5 = SwiftLanguageVersion(uncheckedString: "5")

    /// The list of known Swift language versions.
    public static let knownSwiftLanguageVersions = [
        v3, v4, v4_2, v5,
    ]

    /// The raw value of the language version.
    //
    // This should be passed as a value to Swift compiler's -swift-version flag.
    public let rawValue: String

    /// The underlying backing store.
    private let _version: Version

    /// Regex for parsing the Swift language version.
    private static let regex = try! RegEx(pattern: "^(\\d+)(?:\\.(\\d+))?(?:\\.(\\d+))?$")

    /// Create an instance of Swift language version from the given string.
    ///
    // The Swift language version is not officially fixed but we require it to
    // be a valid SemVer-like string.
    public init?(string: String) {
        let parsedVersion = SwiftLanguageVersion.regex.matchGroups(in: string)
        guard parsedVersion.count == 1, parsedVersion[0].count == 3 else {
            return nil
        }
        let major = Int(parsedVersion[0][0])!
        let minor = parsedVersion[0][1].isEmpty ? 0 : Int(parsedVersion[0][1])!
        let patch = parsedVersion[0][2].isEmpty ? 0 : Int(parsedVersion[0][2])!

        self.rawValue = string
        self._version = Version(major, minor, patch)
    }

    /// Create an instance assuming the string is valid.
    private init(uncheckedString string: String) {
        self.init(string: string)!
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        return rawValue
    }

    // MARK: - Comparable

    public static func == (lhs: SwiftLanguageVersion, rhs: SwiftLanguageVersion) -> Bool {
        return lhs._version == rhs._version
    }

    public static func < (lhs: SwiftLanguageVersion, rhs: SwiftLanguageVersion) -> Bool {
        return lhs._version < rhs._version
    }

    // MAKR: - Compare with ToolsVersion

    public static func == (lhs: SwiftLanguageVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version == rhs._version
    }

    public static func < (lhs: SwiftLanguageVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }

    public static func <= (lhs: SwiftLanguageVersion, rhs: ToolsVersion) -> Bool {
        return (lhs < rhs) || (lhs == rhs)
    }
}

extension SwiftLanguageVersion: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(uncheckedString: rawValue)
    }
}
