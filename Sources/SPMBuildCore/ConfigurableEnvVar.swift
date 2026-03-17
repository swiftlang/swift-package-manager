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

package enum ConfigurableEnvVar: String {
    /// SBOM specification(s) to generate (comma-separated list)
    case SWIFTPM_BUILD_SBOM_SPEC

    /// Directory path to generate SBOM(s) in
    case SWIFTPM_BUILD_SBOM_OUTPUT_DIR

    /// Filter SBOM components and dependencies by entity (package, product, or both)
    case SWIFTPM_BUILD_SBOM_FILTER

    /// Whether to treat SBOM generation errors as warnings
    case SWIFTPM_BUILD_SBOM_WARNING_ONLY

    package func getEnvVar() -> String? {
        ProcessInfo.processInfo.environment[self.rawValue]
    }
}
