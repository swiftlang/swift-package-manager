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

import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import struct Basics.Environment
import struct Basics.EnvironmentKey

public var SupportedBuildSystemOnAllPlatforms: [BuildSystemProvider.Kind] = BuildSystemProvider.Kind.allCases.filter { $0 != .xcode }

public var SupportedBuildSystemOnPlatform: [BuildSystemProvider.Kind] {
    #if os(macOS)
        BuildSystemProvider.Kind.allCases
    #else
        SupportedBuildSystemOnAllPlatforms
    #endif
}

public struct BuildData {
    public let buildSystem: BuildSystemProvider.Kind
    public let config: BuildConfiguration
}

package let TEST_ONLY_DEBUG_ENV_VAR = EnvironmentKey("SWIFTPM_TEST_ONLY_DEBUG_BUILD_CONFIGURATION")
public func getBuildData(for buildSystems: [BuildSystemProvider.Kind]) -> [BuildData] {
    let buildConfigurations: [BuildConfiguration]
    if let value = Environment.current[TEST_ONLY_DEBUG_ENV_VAR], value.isTruthy {
        buildConfigurations = [.debug]
    } else {
        buildConfigurations = BuildConfiguration.allCases
    }
    return buildSystems.flatMap { buildSystem in
        buildConfigurations.compactMap { config in
            return BuildData(buildSystem: buildSystem, config: config)
        }
    }
}


extension String {
    package var isTruthy: Bool {
        switch self.lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }
}