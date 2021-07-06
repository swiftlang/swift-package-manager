// PackageModel/ToolsVersionSpecificationGeneration.swift
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// This file contains an extension to `ToolsVersion` that implements the generation of a Swift tools version specification from a `ToolsVersion` instance.
///
// -----------------------------------------------------------------------------

extension ToolsVersion {
    // TODO: Add options for whitespace styles.
    /// Returns a Swift tools version specification specifying the version to the given precision.
    /// - Parameter resolution: The precision to which the version specifier follows the version.
    /// - Returns: A  Swift tools version specification specifying the version to the given precision.
    public func specification(resolution: SpecifierResolution = .automatic) -> String {
        var versionSpecifier = "\(major).\(minor)"
        switch resolution {
        case .automatic:
            // If the patch version is not zero, then the resolution is at patch version.
            if patch != 0 { fallthrough }
        case .patch:
            versionSpecifier = "\(versionSpecifier).\(patch)"
        case .minor:
            break
        }
        return "// swift-tools-version:\(self < .v5_4 ? "" : " ")\(versionSpecifier)"
    }
    
    /// The precision to which a version specifier follows the version it describes.
    public enum SpecifierResolution {
        /// The patch version is included if and only if it's not zero.
        case automatic
        /// The version specifier includes only the major and minor versions.
        case minor
        /// The version specifier includes the major, minor, and patch versions.
        case patch
        // Although `ToolsVersion` uses `Version` as its backing store, it discards all pre-release and build metadata.
        // The versioning information ends at the patch version.
    }
}
