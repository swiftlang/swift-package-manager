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

import Foundation
import struct Basics.EnvironmentKey

package enum ConfigurableEnvVar: String, CaseIterable {
    /// SBOM specification(s) to generate (comma-separated list)
    case SWIFTPM_BUILD_SBOM_SPEC

    /// Directory path to generate SBOM(s) in
    case SWIFTPM_BUILD_SBOM_OUTPUT_DIR

    /// Filter SBOM components and dependencies by entity (package, product, or both)
    case SWIFTPM_BUILD_SBOM_FILTER

    /// Whether to treat SBOM generation errors as warnings
    case SWIFTPM_BUILD_SBOM_WARNING_ONLY

    /// Bearer token to be provided for all package registry requests
    case SWIFTPM_REGISTRY_TOKEN

    /// Username for Basic authentication credentials provided to all package registries
    case SWIFTPM_REGISTRY_LOGIN

    /// Password for Basic authentication credentials provided to all package registries
    case SWIFTPM_REGISTRY_PASSWORD

    /// Token for HTTP downloads of binary artifacts and prebuilts; does not affect git operations
    case SWIFTPM_SOURCE_CONTROL_TOKEN

    /// Inline netrc-formatted content for per-host credentials
    case SWIFTPM_NETRC_DATA

    private var isCacheable: Bool {
        switch self {
        case .SWIFTPM_BUILD_SBOM_SPEC: false
        case .SWIFTPM_BUILD_SBOM_OUTPUT_DIR: false
        case .SWIFTPM_BUILD_SBOM_FILTER: false
        case .SWIFTPM_BUILD_SBOM_WARNING_ONLY: false
        case .SWIFTPM_REGISTRY_TOKEN: false
        case .SWIFTPM_REGISTRY_LOGIN: false
        case .SWIFTPM_REGISTRY_PASSWORD: false
        case .SWIFTPM_SOURCE_CONTROL_TOKEN: false
        case .SWIFTPM_NETRC_DATA: false

        }
    }

    package static func nonCachableEnvVars() -> Set<EnvironmentKey> {
        return Set(
            Self.allCases.filter { !$0.isCacheable }
                .map { variable in
                    EnvironmentKey(variable.rawValue)
                }
        )
    }

    package func value(from environment: Environment) -> String? {
        environment[EnvironmentKey(self.rawValue)]
    }
}
