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

package enum Spec: String, Codable, Equatable, CaseIterable, Comparable {
    case cyclonedx
    case spdx
    case cyclonedx1
    case spdx3
    // case .cyclonedx2, for future major versions of CycloneDX
    // case .spdx4, for future major versions of SPDX

    package var defaultValueDescription: String {
        let (_, version) = self.latestSpec
        switch self {
        case .cyclonedx: return "Most recent major version of CycloneDX supported by SwiftPM (currently: \(version))"
        case .spdx: return "Most recent major version of SPDX supported by SwiftPM (currently: \(version))"
        case .cyclonedx1: return "Most recent minor version of CycloneDX v1 supported by SSwiftPMPM  (currently: \(version))"
        case .spdx3: return "Most recent minor version of SPDX v3 supported by SwiftPM (currently: \(version))"
        // case .cyclonedx2
        // case .spdx4
        }
    }

    package static func < (lhs: Spec, rhs: Spec) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    internal var supportsCycloneDX: Bool {
        switch self {
        case .cyclonedx, .cyclonedx1: // cyclonedx2
            true
        case .spdx, .spdx3: // spdx4
            false
        }
    }

    internal var supportsSPDX: Bool {
        switch self {
        case .spdx, .spdx3: // spdx 4
            true
        case .cyclonedx, .cyclonedx1: // cyclonedx2
            false
        }
    }

    /// Returns the concrete spec type and version for generic spec cases.
    internal var latestSpec: (type: Spec, version: String) {
        switch self {
        case .cyclonedx, .cyclonedx1: // cyclonedx2
            (.cyclonedx1, CycloneDXConstants.cyclonedx1SpecVersion)
        case .spdx, .spdx3: // spdx4
            (.spdx3, SPDXConstants.spdx3SpecVersion)
        }
    }
}

extension Spec: ExpressibleByArgument {
    package init?(argument: String) {
        self.init(rawValue: argument)
    }
}

internal struct SBOMSpec: Codable, Equatable, Hashable {
    internal let type: Spec
    internal let version: String

    internal init(
        type: Spec,
        version: String
    ) {
        self.type = type
        self.version = version
    }
}
