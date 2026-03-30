//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

internal struct SPDXConstants: Codable, Equatable {
    /// The latest minor version of SPDX v3.x (from SBOMVersionRegistry)
    internal static var spdx3SpecVersion: String {
        SBOMVersionRegistry.spdx3LatestMinor
    }
    
    /// The JSON-LD context URL for SPDX v3.x
    /// This is embedded as a field in the SBOM, and points to an official schema URL on the SPDX website
    internal static var spdx3Context: String {
        "https://spdx.org/rdf/\(spdx3SpecVersion)/spdx-context.jsonld"
    }
    
    /// The schema filename for SPDX v3.x (without .json extension) that's bundled as an internal resource with SwiftPM
    internal static var spdx3SchemaFile: String {
        "spdx-\(spdx3SpecVersion).schema"
    }
    
    /// The root creation info ID used in SPDX documents
    internal static let spdxRootCreationInfoID = "_:creationInfo"
    
    // Future major versions (uncomment when SPDX 4.0 is released):
    // /// The latest minor version of SPDX v4.x (from SBOMVersionRegistry)
    // internal static var spdx4SpecVersion: String {
    //     SBOMVersionRegistry.spdx4LatestMinor
    // }
    //
    // /// The JSON-LD context URL for SPDX v4.x
    // internal static var spdx4Context: String {
    //     "https://spdx.org/rdf/\(spdx4SpecVersion)/spdx-context.jsonld"
    // }
    //
    // /// The schema filename for SPDX v4.x (without .json extension)
    // internal static var spdx4SchemaFile: String {
    //     "spdx-\(spdx4SpecVersion).schema"
    // }
}
