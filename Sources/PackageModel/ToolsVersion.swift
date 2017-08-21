/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

import Foundation
import Utility

/// Tools version represents version of the Swift toolchain.
public struct ToolsVersion: CustomStringConvertible, Comparable {

    /// The default tool version if a the tools version file is absent.
    public static let defaultToolsVersion = ToolsVersion(version: "3.1.0")

    /// The current tools version in use.
    public static let currentToolsVersion = ToolsVersion(string:
        "\(Versioning.currentVersion.major)." +
        "\(Versioning.currentVersion.minor)." +
        "\(Versioning.currentVersion.patch)")!

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
    private let _version: Version

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

    public static func == (lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version == rhs._version
    }

    public static func < (lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }
}
