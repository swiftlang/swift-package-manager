//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

import struct TSCUtility.Version

/// Tools version represents version of the Swift toolchain.
public struct ToolsVersion: Equatable, Hashable, Codable, Sendable {

    public static let v3 = ToolsVersion(version: "3.1.0")
    public static let v4 = ToolsVersion(version: "4.0.0")
    public static let v4_2 = ToolsVersion(version: "4.2.0")
    public static let v5 = ToolsVersion(version: "5.0.0")
    public static let v5_2 = ToolsVersion(version: "5.2.0")
    public static let v5_3 = ToolsVersion(version: "5.3.0")
    public static let v5_4 = ToolsVersion(version: "5.4.0")
    public static let v5_5 = ToolsVersion(version: "5.5.0")
    public static let v5_6 = ToolsVersion(version: "5.6.0")
    public static let v5_7 = ToolsVersion(version: "5.7.0")
    public static let v5_8 = ToolsVersion(version: "5.8.0")
    public static let v5_9 = ToolsVersion(version: "5.9.0")
    public static let v5_10 = ToolsVersion(version: "5.10.0")
    public static let v6_0 = ToolsVersion(version: "6.0.0")
    public static let v6_1 = ToolsVersion(version: "6.1.0")
    public static let v6_2 = ToolsVersion(version: "6.2.0")
    public static let vNext = ToolsVersion(version: "999.0.0")

    /// The current tools version in use.
    public static let current = ToolsVersion(string:
        "\(SwiftVersion.current.major)." +
        "\(SwiftVersion.current.minor)." +
        "\(SwiftVersion.current.patch)")!

    /// The minimum tools version that is required by the package manager.
    public static let minimumRequired: ToolsVersion = .v4

    /// Regex pattern to parse tools version. The format is SemVer 2.0 with an
    /// addition that specifying the patch version is optional.
    static let toolsVersionRegex = try! NSRegularExpression(
        pattern: #"""
                 ^
                 (\d+)\.(\d+)(?:\.(\d+))?
                 (
                     \-[A-Za-z\d]+(?:\.[A-Za-z\d]+)*
                 )?
                 (
                     \+[A-Za-z\d]+(?:\.[A-Za-z\d]+)*
                 )?
                 $
                 """#,
        options: [.allowCommentsAndWhitespace]
    )

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

    /// Returns the tools version with zeroed patch number.
    public var zeroedPatch: ToolsVersion {
        return ToolsVersion(version: Version(major, minor, 0))
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

    private enum ValidationResult {
        case valid
        case unsupportedToolsVersion
        case requireNewerTools
    }

    private func _validateToolsVersion(_ currentToolsVersion: ToolsVersion) -> ValidationResult {
        // We don't want to throw any error when using the special vNext version.
        if SwiftVersion.current.isDevelopment && self == .vNext {
            return .valid
        }

        // Make sure the package has the right minimum tools version.
        guard self >= .minimumRequired else {
            return .unsupportedToolsVersion
        }

        // Make sure the package isn't newer than the current tools version.
        guard currentToolsVersion >= self else {
            return .requireNewerTools
        }

        return .valid
    }

    /// Returns true if the tools version is valid and can be used by this
    /// version of the package manager.
    public func validateToolsVersion(_ currentToolsVersion: ToolsVersion) -> Bool {
        return self._validateToolsVersion(currentToolsVersion) == .valid
    }

    public func validateToolsVersion(
        _ currentToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageVersion: String? = .none
    ) throws {
        switch self._validateToolsVersion(currentToolsVersion) {
        case .valid:
            break
        case .unsupportedToolsVersion:
            throw UnsupportedToolsVersion(
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                currentToolsVersion: currentToolsVersion,
                packageToolsVersion: self
            )
        case .requireNewerTools:
            throw RequireNewerTools(
                packageIdentity: packageIdentity,
                packageVersion: packageVersion,
                installedToolsVersion: currentToolsVersion,
                packageToolsVersion: self
            )
        }
    }

    /// The subpath to the PackageDescription runtime library.
    public var runtimeSubpath: RelativePath {
        if self < .v4_2 {
            return try! RelativePath(validating: "4") // try! safe
        }
        return try! RelativePath(validating: "4_2") // try! safe
    }

    /// The swift language version based on this tools version.
    public var swiftLanguageVersion: SwiftLanguageVersion {
        switch major {
        case 4:
            // If the tools version is less than 4.2, use language version 4.
            if minor < 2 {
                return .v4
            }

            // Otherwise, use 4.2
            return .v4_2
        case 5:
            return .v5
        default:
            // Anything above 5 major version uses version 6.
            return .v6
        }
    }
}

extension ToolsVersion {
    /// The list of version specific identifiers to search when attempting to
    /// load version specific package or version information, in order of
    /// preference.
    public var versionSpecificKeys: [String] {
        return [
            "@swift-\(self.major).\(self.minor).\(self.patch)",
            "@swift-\(self.major).\(self.minor)",
            "@swift-\(self.major)",
        ]
    }
}

extension ToolsVersion: CustomStringConvertible {
    public var description: String {
        return self._version.description
    }
}

extension ToolsVersion: Comparable {
    public static func < (lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }
}
