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
/// See `Sources/SBOMModel/README.md` for detailed documentation on version management.
internal struct SBOMVersionRegistry {
    // MARK: - CycloneDX Versions
    
    /// Latest minor version of CycloneDX v1.x
    internal static let cycloneDX1LatestMinor = "1.7"
    
    // Future major versions (uncomment when released):
    // internal static let cycloneDX2LatestMinor = "2.0"
    
    // MARK: - SPDX Versions
    
    /// Latest minor version of SPDX v3.x
    internal static let spdx3LatestMinor = "3.0.1"
    
    // Future major versions (uncomment when released):
    // internal static let spdx4LatestMinor = "4.0"
    
    // MARK: - Version Resolution
    
    /// Returns the latest supported version for a given spec type.
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