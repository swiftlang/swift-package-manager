/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Testing

public struct TestBuildData {
    public let buildData: [BuildData]
    public let tags: any TestTrait
}

public let buildDataUsingAllBuildSystemWithTags = TestBuildData(
    buildData: getBuildData(for: SupportedBuildSystemOnPlatform),
    tags: .tags(
        .Feature.CommandLineArguments.BuildSystem,
        .Feature.CommandLineArguments.Configuration
    )
)

public let buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags = TestBuildData(
    buildData: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    tags: .tags(
        .Feature.CommandLineArguments.BuildSystem,
        .Feature.CommandLineArguments.Configuration
    )
)
