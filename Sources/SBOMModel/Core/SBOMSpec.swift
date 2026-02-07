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

import ArgumentParser

/// SBOM specification types supported by SwiftPM.
/// All version numbers are managed centrally in `SBOMVersionRegistry`.
/// 
/// This file only needs to be changed with new major versions like CycloneDX 2 or SPDX 4.

/// Spec is the enum used for the user's CLI arguments
package enum Spec: String, Codable, Equatable, CaseIterable, ExpressibleByArgument {
    /// Latest major version of CycloneDX (currently maps to `cyclonedx1`)
    case cyclonedx
    
    /// Latest major version of SPDX (currently maps to `spdx3`)
    case spdx
    
    /// CycloneDX v1.x - Latest minor version
    case cyclonedx1
    
    /// SPDX v3.x - Latest minor version
    case spdx3
    
    // Future major versions (uncomment when released):
    //
    // /// CycloneDX v2.x - Latest minor version
    // ///
    // /// Add this case when CycloneDX 2.0 is released.
    // /// Update `.cyclonedx` to map to this case in `latestSpec`.
    // case cyclonedx2
    //
    // /// SPDX v4.x - Latest minor version
    // ///
    // /// Add this case when SPDX 4.0 is released.
    // /// Update `.spdx` to map to this case in `latestSpec`.
    // case spdx4

    package var defaultValueDescription: String {
        let version = SBOMVersionRegistry.getLatestVersion(for: SBOMSpec(spec: self))
        switch self {
        case .cyclonedx: return "Most recent major version of CycloneDX supported by SwiftPM (currently: \(version))"
        case .spdx: return "Most recent major version of SPDX supported by SwiftPM (currently: \(version))"
        case .cyclonedx1: return "Most recent minor version of CycloneDX v1 supported by SwiftPM (currently: \(version))"
        case .spdx3: return "Most recent minor version of SPDX v3 supported by SwiftPM (currently: \(version))"
        // case .cyclonedx2: return "Most recent minor version of CycloneDX v2 supported by SwiftPM (currently: \(version))"
        // case .spdx4: return "Most recent minor version of SPDX v4 supported by SwiftPM (currently: \(version))"
        }
    }
}

/// Internal representation of a concrete SBOM specification.
internal struct SBOMSpec: Codable, Equatable, Hashable, Comparable {

    internal enum ConcreteSpec: String, Codable, Equatable, CaseIterable, Comparable {
        case cyclonedx1
        case spdx3
        // case cyclonedx2
        // case spdx4

        package static func < (lhs: ConcreteSpec, rhs: ConcreteSpec) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    internal let concreteSpec: ConcreteSpec
    
    internal var versionString: String {
        SBOMVersionRegistry.getLatestVersion(for: self)
    }

        /// Returns `true` if this spec type supports CycloneDX format.
    internal var supportsCycloneDX: Bool {
        switch self.concreteSpec {
        case .cyclonedx1: // .cyclonedx2
            true
        case .spdx3: // .spdx4
            false
        }
    }

    /// Returns `true` if this spec type supports SPDX format.
    internal var supportsSPDX: Bool {
        switch self.concreteSpec {
        case .spdx3: // .spdx4
            true
        case .cyclonedx1: // .cyclonedx2
            false
        }
    }

    internal init(spec: Spec) {
        switch spec {
            case .cyclonedx, .cyclonedx1:
                self.concreteSpec = .cyclonedx1
            case .spdx, .spdx3:
                self.concreteSpec = .spdx3
        }
    }

    internal static func < (lhs: SBOMSpec, rhs: SBOMSpec) -> Bool {
        lhs.concreteSpec < rhs.concreteSpec
    }
}
