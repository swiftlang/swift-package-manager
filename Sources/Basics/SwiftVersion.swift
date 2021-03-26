/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@_implementationOnly import TSCclibc

public struct SwiftVersion {
    /// The version number.
    public var version: (major: Int, minor: Int, patch: Int)

    /// Whether or not this is a development version.
    public var isDevelopment: Bool

    /// Build information, as an unstructured string.
    public var buildIdentifier: String?

    /// The major component of the version number.
    public var major: Int { return self.version.major }
    /// The minor component of the version number.
    public var minor: Int { return self.version.minor }
    /// The patch component of the version number.
    public var patch: Int { return self.version.patch }

    /// The version as a readable string.
    public var displayString: String {
        var result = "\(major).\(minor).\(patch)"
        if self.isDevelopment {
            result += "-dev"
        }
        if let buildIdentifier = self.buildIdentifier {
            result += " (" + buildIdentifier + ")"
        }
        return result
    }

    /// The complete product version display string (including the name).
    public var completeDisplayString: String {
        var vendorPrefix = String(cString: SPM_VendorNameString())
        if !vendorPrefix.isEmpty {
            vendorPrefix += " "
        }
        return vendorPrefix + "Swift Package Manager - Swift " + self.displayString
    }

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

extension SwiftVersion {
    /// The current version of the package manager.
    public static let currentVersion = SwiftVersion(
        version: (5, 5, 0),
        isDevelopment: true,
        buildIdentifier: getBuildIdentifier()
    )
}

private func getBuildIdentifier() -> String? {
    let buildIdentifier = String(cString: SPM_BuildIdentifierString())
    return buildIdentifier.isEmpty ? nil : buildIdentifier
}
