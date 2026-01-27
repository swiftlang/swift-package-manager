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

/// Central registry for managing SBOM specification versions.
///
/// This registry maintains the most recent minor version for each major version
/// of supported SBOM specifications (CycloneDX and SPDX).
///
/// SwiftPM supports **only the most recent minor version** of each **major version**:
/// - When a new minor version is released (e.g., CycloneDX 1.8), drop the old minor (1.7)
/// - When a new major version is released (e.g., CycloneDX 2.0), maintain both major versions
internal struct SBOMVersionRegistry {
    // MARK: - CycloneDX Versions
    
    /// Latest minor version of CycloneDX v1.x
    ///
    /// **Update Process**: When CycloneDX 1.8 is released:
    /// 1. Change this value to "1.8"
    /// 2. Replace schema file: `cyclonedx-1.7.schema.json` → `cyclonedx-1.8.schema.json`
    /// 3. Update tests to expect version 1.8
    internal static let cycloneDX1LatestMinor = "1.7"
    
    // Future major versions (uncomment when released):
    // /// Latest minor version of CycloneDX v2.x
    // ///
    // /// **Update Process**: When CycloneDX 2.1 is released:
    // /// 1. Change this value to "2.1"
    // /// 2. Replace schema file: `cyclonedx-2.0.schema.json` → `cyclonedx-2.1.schema.json`
    // /// 3. Update tests to expect version 2.1
    // /// 4. Keep `cycloneDX1LatestMinor` - both major versions are supported
    // internal static let cycloneDX2LatestMinor = "2.0"
    
    // MARK: - SPDX Versions
    
    /// Latest minor version of SPDX v3.x
    ///
    /// **Update Process**: When SPDX 3.1 is released:
    /// 1. Change this value to "3.1"
    /// 2. Replace schema file: `spdx-3.0.1.schema.json` → `spdx-3.1.schema.json`
    /// 3. Update tests to expect version 3.1
    internal static let spdx3LatestMinor = "3.0.1"
    
    // Future major versions (uncomment when released):
    // /// Latest minor version of SPDX v4.x
    // ///
    // /// **Update Process**: When SPDX 4.1 is released:
    // /// 1. Change this value to "4.1"
    // /// 2. Replace schema file: `spdx-4.0.schema.json` → `spdx-4.1.schema.json`
    // /// 3. Update tests to expect version 4.1
    // /// 4. Keep `spdx3LatestMinor` - both major versions are supported
    // internal static let spdx4LatestMinor = "4.0"
    
    // MARK: - Version Resolution
    
    /// Returns the latest supported version for a given spec type.
    ///
    /// - Parameter spec: The SBOM specification type
    /// - Returns: The version string for the latest minor version of that spec
    internal static func getLatestVersion(for spec: SBOMSpec) -> String {
        switch spec.concreteSpec {
        case .cyclonedx1:
            return cycloneDX1LatestMinor
        case .spdx3:
            return spdx3LatestMinor
        // case .cyclonedx2:
        //     return cycloneDX2LatestMinor
        // case .spdx4:
        //     return spdx4LatestMinor
        }
    }
}

// MARK: - Adding New Major Versions

/*
 ## How to Add Support for a New Major Version
 
 When a new major version is released (e.g., CycloneDX 2.0 or SPDX 4.0), follow these steps:
 
 ### Step 1: Update SBOMVersionRegistry.swift (this file)
 
 Uncomment and set the appropriate version constant:
 ```swift
 internal static let cycloneDX2LatestMinor = "2.0"  // or spdx4LatestMinor = "4.0"
 ```
 
 Add the case to `getLatestVersion(for:)`:
 ```swift
 case .cyclonedx2:
     return cycloneDX2LatestMinor
 ```
 
 ### Step 2: Update SBOMSpec.swift
 
 Add new case to the `Spec` enum:
 ```swift
 case cyclonedx2  // or spdx4
 ```
 
 Update all switch statements to handle the new case:
 
 ### Step 3: Create New Constants
 
 Add to CycloneDXConstants.swift (or SPDXConstants.swift):
 ```swift
 internal static var cyclonedx2SpecVersion: String {
     SBOMVersionRegistry.cycloneDX2LatestMinor
 }
 internal static var cyclonedx2Schema: String {
     "http://cyclonedx.org/schema/bom-\(cyclonedx2SpecVersion).schema.json"
 }
 internal static var cyclonedx2SchemaFile: String {
     "cyclonedx-\(cyclonedx2SpecVersion).schema"
 }
 ```
 
 ### Step 4: Update Encoder and Converter
 
 In SBOMEncoder.swift:
 - Update `encodeSBOMData(spec:)` switch statement
 - Update `getSchemaFilename(from:)` switch statement
 
 In CycloneDXConverter.swift (or SPDXConverter.swift):
 - Add converter methods for new major version if format changed
 - Or reuse existing converter if format is compatible
 
 ### Step 5: Add Schema File
 
 Add the schema file to Resources:
 - `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-2.0.schema.json`
 - Or: `Sources/SBOMModel/SPDX/Resources/spdx-4.0.schema.json`
 
 ### Step 6: Update Tests
 
 - Add test fixtures for new major version
 - Update test expectations
 - Verify both old and new major versions work correctly
 
 */

// MARK: - Updating Minor Versions

/*
 ## How to Update to a New Minor Version
 
 When a new minor version is released (e.g., CycloneDX 1.8 or SPDX 3.1), follow these steps:
 
 ### Step 1: Update Version Constant
 
 In SBOMVersionRegistry.swift (this file), change the version string:
 ```swift
 // Before:
 internal static let cycloneDX1LatestMinor = "1.7"
 
 // After:
 internal static let cycloneDX1LatestMinor = "1.8"
 ```
 
 ### Step 2: Replace Schema File
 
 In the Resources directory:
 - **Delete**: `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-1.7.schema.json`
 - **Add**: `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-1.8.schema.json`
 
 ### Step 3: Update Tests
 
 Update test expectations to use the new version:
 ```swift
 // Before:
 XCTAssertEqual(spec.version, "1.7")
 
 // After:
 XCTAssertEqual(spec.version, "1.8")
 ```
 
 ### Step 4: Verify Constants
 
 No code changes needed! The constants automatically use the new version:
 - `CycloneDXConstants.cyclonedx1SpecVersion` → "1.8"
 - `CycloneDXConstants.cyclonedx1Schema` → "...bom-1.8.schema.json"
 - `CycloneDXConstants.cyclonedx1SchemaFile` → "cyclonedx-1.8.schema"
 
 ### Step 5: Test Thoroughly
 
 - Run all SBOM tests
 - Generate sample SBOMs and validate against new schema
 - Verify backward compatibility if needed
 
 */