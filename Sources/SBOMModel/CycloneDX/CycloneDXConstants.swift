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

internal struct CycloneDXConstants: Codable, Equatable {
    /// The latest minor version of CycloneDX v1.x (from SBOMVersionRegistry)
    internal static var cyclonedx1SpecVersion: String {
        SBOMVersionRegistry.cycloneDX1LatestMinor
    }
    
    /// The JSON schema URL for CycloneDX v1.x
    /// This is embedded as a field in the SBOM, and points to an official schema URL on the CycloneDX website
    internal static var cyclonedx1Schema: String {
        "http://cyclonedx.org/schema/bom-\(cyclonedx1SpecVersion).schema.json"
    }
    
    /// The schema filename for CycloneDX v1.x (without .json extension) that's bundled as an internal resource with SwiftPM
    internal static var cyclonedx1SchemaFile: String {
        "cyclonedx-\(cyclonedx1SpecVersion).schema"
    }
    
    // Future major versions (uncomment when CycloneDX 2.0 is released):
    // /// The latest minor version of CycloneDX v2.x (from SBOMVersionRegistry)
    // internal static var cyclonedx2SpecVersion: String {
    //     SBOMVersionRegistry.cycloneDX2LatestMinor
    // }
    //
    // /// The JSON schema URL for CycloneDX v2.x
    // internal static var cyclonedx2Schema: String {
    //     "http://cyclonedx.org/schema/bom-\(cyclonedx2SpecVersion).schema.json"
    // }
    //
    // /// The schema filename for CycloneDX v2.x (without .json extension)
    // internal static var cyclonedx2SchemaFile: String {
    //     "cyclonedx-\(cyclonedx2SpecVersion).schema"
    // }
}
