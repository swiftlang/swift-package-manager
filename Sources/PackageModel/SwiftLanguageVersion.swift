//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import struct TSCBasic.RegEx

import struct TSCUtility.Version

/// Represents a Swift language version.
public struct SwiftLanguageVersion: Hashable, Sendable {

    /// Swift language version 3.
    public static let v3 = SwiftLanguageVersion(uncheckedString: "3")

    /// Swift language version 4.
    public static let v4 = SwiftLanguageVersion(uncheckedString: "4")

    /// Swift language version 4.2.
    public static let v4_2 = SwiftLanguageVersion(uncheckedString: "4.2")

    /// Swift language version 5.
    public static let v5 = SwiftLanguageVersion(uncheckedString: "5")

    /// Swift language version 6.
    public static let v6 = SwiftLanguageVersion(uncheckedString: "6")

    /// The list of known Swift language versions.
    public static let knownSwiftLanguageVersions = [
        v3, v4, v4_2, v5, v6
    ]

    /// The list of supported Swift language versions for this toolchain.
    public static let supportedSwiftLanguageVersions = [
        v4, v4_2, v5, v6
    ]

    /// The raw value of the language version.
    //
    // This should be passed as a value to Swift compiler's -swift-version flag.
    public let rawValue: String

    /// The underlying backing store.
    private let _version: Version

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

    /// Regex for parsing the Swift language version.
    private static let regex = try! RegEx(pattern: #"^(\d+)(?:\.(\d+))?(?:\.(\d+))?$"#)

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
}

extension SwiftLanguageVersion: CustomStringConvertible {
    public var description: String {
        return rawValue
    }
}

extension SwiftLanguageVersion: Equatable {
    public static func == (lhs: SwiftLanguageVersion, rhs: SwiftLanguageVersion) -> Bool {
        return lhs._version == rhs._version
    }
}

extension SwiftLanguageVersion: Comparable {
    public static func < (lhs: SwiftLanguageVersion, rhs: SwiftLanguageVersion) -> Bool {
        return lhs._version < rhs._version
    }
}

// MARK: - Compare with ToolsVersion

extension SwiftLanguageVersion {
    public static func == (lhs: SwiftLanguageVersion, rhs: ToolsVersion) -> Bool {
        return (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }

    public static func < (lhs: SwiftLanguageVersion, rhs: ToolsVersion) -> Bool {
        return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
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
