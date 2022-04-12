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

// -----------------------------------------------------------------------------
///
/// This file contains an extension to `ToolsVersion` that implements the generation of a Swift tools version specification from a `ToolsVersion` instance.
///
// -----------------------------------------------------------------------------

extension ToolsVersion {
    // TODO: Add options for whitespace styles.
    /// Returns a Swift tools version specification specifying the version to the given precision.
    /// - Parameter leastSignificantVersion: The precision to which the version specifier follows the version.
    /// - Returns: A  Swift tools version specification specifying the version to the given precision.
    public func specification(roundedTo leastSignificantVersion: LeastSignificantVersion = .automatic) -> String {
        var versionSpecifier = "\(major).\(minor)"
        switch leastSignificantVersion {
        case .automatic:
            // If the patch version is not zero, then it's included in the Swift tools version specification.
            if patch != 0 { fallthrough }
        case .patch:
            versionSpecifier = "\(versionSpecifier).\(patch)"
        case .minor:
            break
        }
        return "// swift-tools-version:\(self < .v5_4 ? "" : " ")\(versionSpecifier)"
    }

    /// The least significant version to round to.
    public enum LeastSignificantVersion {
        /// The patch version is the least significant if and only if it's not zero. Otherwise, the minor version is the least significant.
        case automatic
        /// The minor version is the least significant.
        case minor
        /// The patch version is the least significant.
        case patch
        // Although `ToolsVersion` uses `Version` as its backing store, it discards all pre-release and build metadata.
        // The versioning information ends at the patch version.
    }
}
