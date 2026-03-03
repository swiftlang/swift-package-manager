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

    public init(
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
    ) {
        self.buildSystem = buildSystem
        self.config = config
    }
}

public func getBuildData(for buildSystems: [BuildSystemProvider.Kind]) -> [BuildData] {
    buildSystems.flatMap { buildSystem in
        BuildConfiguration.allCases.compactMap { config in
            return BuildData(
                buildSystem: buildSystem,
                config: config,
            )
        }
    }
}
